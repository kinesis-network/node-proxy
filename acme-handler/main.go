package main

import (
	"context"
	"crypto/tls"
	"crypto/x509"
	"encoding/base64"
	"fmt"
	"log"
	"net"
	"net/http"
	"os"
	"os/signal"
	"strings"
	"sync"
	"syscall"
	"time"

	"github.com/julienschmidt/httprouter"
	"github.com/redis/go-redis/v9"
)

func main() {
	// Load Environment Variables
	socketPath := os.Getenv("ACME_SOCKET")
	redisAddrs := os.Getenv("REDIS_ADDRS") // comma-separated list
	redisPassword := os.Getenv("REDIS_PASSWORD")
	masterName := os.Getenv("REDIS_MASTER_NAME")
	caCertBase64 := os.Getenv("CACERT_BASE64")
	// The same CA as a mounted PEM file, instead of CACERT_BASE64.
	caFile := os.Getenv("REDIS_CA_FILE")
	// A client certificate and key as mounted PEM files. Redis logs the
	// client in as the ACL user its CN names, so no password is needed.
	certFile := os.Getenv("REDIS_CERT_FILE")
	keyFile := os.Getenv("REDIS_KEY_FILE")

	if redisAddrs == "" || masterName == "" {
		log.Fatal("Missing required environment variables: REDIS_ADDRS or REDIS_MASTER_NAME")
	}

	// Setup TLS Config from the CA (Base64 or file)
	tlsConfig := &tls.Config{}
	var caCert []byte
	switch {
	case caCertBase64 != "" && caFile != "":
		log.Fatal("Set CACERT_BASE64 or REDIS_CA_FILE, not both")
	case caCertBase64 != "":
		var err error
		if caCert, err = base64.StdEncoding.DecodeString(caCertBase64); err != nil {
			log.Fatalf("Failed to decode CACERT_BASE64: %v", err)
		}
	case caFile != "":
		var err error
		if caCert, err = os.ReadFile(caFile); err != nil {
			log.Fatalf("Failed to read REDIS_CA_FILE: %v", err)
		}
	}
	if caCert != nil {
		caCertPool := x509.NewCertPool()
		if ok := caCertPool.AppendCertsFromPEM(caCert); !ok {
			log.Fatal("Failed to append CA certificate to pool")
		}
		tlsConfig.RootCAs = caCertPool
	}

	if (certFile == "") != (keyFile == "") {
		log.Fatal("Set both REDIS_CERT_FILE and REDIS_KEY_FILE, or neither")
	}
	if certFile != "" {
		cc, err := newClientCert(certFile, keyFile)
		if err != nil {
			log.Fatalf("Failed to load the client certificate: %v", err)
		}
		tlsConfig.GetClientCertificate = cc.get
	}

	ctx := context.Background()

	// Initialize Redis Sentinel Client
	rdb := redis.NewFailoverClient(&redis.FailoverOptions{
		MasterName:    masterName,
		SentinelAddrs: strings.Split(redisAddrs, ","),
		Password:      redisPassword,
		TLSConfig:     tlsConfig,
	})

	// Router Setup
	router := httprouter.New()

	// Named parameter ":token" makes extraction trivial
	router.GET("/.well-known/acme-challenge/:token",
		func(w http.ResponseWriter, r *http.Request, ps httprouter.Params) {
			token := ps.ByName("token")

			val, err := rdb.Get(ctx, "acme:"+token).Result()
			if err == redis.Nil {
				msg := fmt.Sprintf("ACME: Token %s not found", token)
				log.Println(msg)
				http.Error(w, msg, http.StatusNotFound)
				return
			} else if err != nil {
				log.Printf("ACME: Redis error: %v", err)
				http.Error(w, "Internal Server Error", http.StatusInternalServerError)
				return
			}

			w.Header().Set("Content-Type", "text/plain")
			fmt.Fprint(w, val)
		},
	)

	// Setup Unix Domain Socket Listener
	// Clean up existing socket file if it exists
	if err := os.RemoveAll(socketPath); err != nil {
		log.Fatal(err)
	}
	listener, err := net.Listen("unix", socketPath)
	if err != nil {
		log.Fatal("Listen error:", err)
	}
	// Set permissions so HAProxy can read/write to the socket
	if err := os.Chmod(socketPath, 0666); err != nil {
		log.Fatal("Chmod error:", err)
	}

	// Handle graceful shutdown (remove socket file on exit)
	c := make(chan os.Signal, 1)
	signal.Notify(c, os.Interrupt, syscall.SIGTERM)
	go func() {
		<-c
		os.Remove(socketPath)
		os.Exit(0)
	}()

	log.Printf("Starting ACME sidecar on %s (Master: %s)", socketPath, masterName)
	log.Fatal(http.Serve(listener, router))
}

// clientCert serves the client certificate in REDIS_CERT_FILE and
// REDIS_KEY_FILE. The certificate is short-lived and renewed in place, so a
// new connection reads the files again when either has changed; until a
// renewed pair loads, the last one that did is kept. Redis checks the
// certificate only on connect, so open connections are not affected.
type clientCert struct {
	certFile, keyFile string

	mu                  sync.Mutex
	cert                *tls.Certificate
	certMtime, keyMtime time.Time
}

func newClientCert(certFile, keyFile string) (*clientCert, error) {
	c := &clientCert{certFile: certFile, keyFile: keyFile}
	if err := c.reload(); err != nil {
		return nil, err
	}
	return c, nil
}

// reload loads the pair when either file changed since the last load. The
// caller holds mu, or c is not shared yet.
func (c *clientCert) reload() error {
	cs, err := os.Stat(c.certFile)
	if err != nil {
		return err
	}
	ks, err := os.Stat(c.keyFile)
	if err != nil {
		return err
	}
	if c.cert != nil && cs.ModTime().Equal(c.certMtime) && ks.ModTime().Equal(c.keyMtime) {
		return nil
	}
	cert, err := tls.LoadX509KeyPair(c.certFile, c.keyFile)
	if err != nil {
		return err
	}
	c.cert, c.certMtime, c.keyMtime = &cert, cs.ModTime(), ks.ModTime()
	if leaf, err := x509.ParseCertificate(cert.Certificate[0]); err == nil {
		log.Printf("Loaded the client certificate: CN=%s, valid until %s",
			leaf.Subject.CommonName, leaf.NotAfter.UTC().Format(time.RFC3339))
	}
	return nil
}

func (c *clientCert) get(*tls.CertificateRequestInfo) (*tls.Certificate, error) {
	c.mu.Lock()
	defer c.mu.Unlock()
	if err := c.reload(); err != nil {
		log.Printf("Keeping the previous client certificate: %v", err)
	}
	return c.cert, nil
}
