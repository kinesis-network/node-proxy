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
	"syscall"

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

	if redisAddrs == "" || masterName == "" {
		log.Fatal("Missing required environment variables: REDIS_ADDRS or REDIS_MASTER_NAME")
	}

	// Setup TLS Config from Base64 CA
	tlsConfig := &tls.Config{}
	if caCertBase64 != "" {
		caCert, err := base64.StdEncoding.DecodeString(caCertBase64)
		if err != nil {
			log.Fatalf("Failed to decode CACERT_BASE64: %v", err)
		}

		caCertPool := x509.NewCertPool()
		if ok := caCertPool.AppendCertsFromPEM(caCert); !ok {
			log.Fatal("Failed to append CA certificate to pool")
		}
		tlsConfig.RootCAs = caCertPool
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
