package main

import (
	"github.com/apache/apisix-go-plugin-runner/pkg/runner"
	_ "upstream-response-transformer/plugins" // Import for plugin registration
)

func main() {
	cfg := runner.RunnerConfig{}
	runner.Run(cfg)
} 