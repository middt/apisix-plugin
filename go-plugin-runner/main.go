package main

import (
	_ "apisix-go-plugin-runner/plugins" // Import for plugin registration

	"github.com/apache/apisix-go-plugin-runner/pkg/runner"
)

func main() {
	cfg := runner.RunnerConfig{}
	runner.Run(cfg)
}
