package main

import (
	"context"
	"fmt"
	"github.com/eniac/mucache/internal/trivial"
	"github.com/eniac/mucache/pkg/slowpoke"
	"github.com/eniac/mucache/pkg/wrappers"
	"net"
	"net/http"
	"sync"
	"os"
	"strings"
)

var lock sync.Mutex
var is_locked bool
var sleep_time int
var payload string // NetPoke: padding so this service's reply moves real bytes

func ep1(ctx context.Context, request *trivial.TrivialRequest) *trivial.TrivialResponse {
	if is_locked {
		lock.Lock()
		slowpoke.CPUSpinTime(sleep_time)
		defer lock.Unlock()
	} else {
		slowpoke.CPUSpinTime(sleep_time)
	}
	resp := trivial.TrivialResponse{A: "ok" + payload}
	return &resp
}

func main() {
	// read env IS_LOCKED
	if os.Getenv("SLEEP_TIME") != "" {
		fmt.Sscanf(os.Getenv("SLEEP_TIME"), "%d", &sleep_time)
	}
	fmt.Println("SLEEP_TIME:", sleep_time)
	if os.Getenv("RESPONSE_PAYLOAD_BYTES") != "" {
		var n int
		fmt.Sscanf(os.Getenv("RESPONSE_PAYLOAD_BYTES"), "%d", &n)
		payload = strings.Repeat("x", n)
	}
	fmt.Println("RESPONSE_PAYLOAD_BYTES:", len(payload))
	if os.Getenv("IS_LOCKED") == "true" {
		is_locked = true
	} else {
		is_locked = false
	}
	fmt.Println("IS_LOCKED:", is_locked)
	http.HandleFunc("/ep1", wrappers.SlowpokeWrapper[trivial.TrivialRequest, trivial.TrivialResponse](ep1, "ep1"))
	slowpoke.SlowpokeInit()
	fmt.Println("Server started on :3000")
	listener, err := net.Listen("tcp", ":3000")
	if err != nil {
		panic(err)
	}
	slowpokeListener := &slowpoke.SlowpokeListener{listener}
	panic(http.Serve(slowpokeListener, nil))
}
