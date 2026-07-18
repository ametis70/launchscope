package main

import (
	"context"
	"fmt"
	"log/slog"
	"net/http"
	"os"
	"time"

	"github.com/ametis70/launchscope/server/internal/api"
	"github.com/ametis70/launchscope/server/internal/apps"
	"github.com/ametis70/launchscope/server/internal/audio"
	"github.com/ametis70/launchscope/server/internal/config"
	"github.com/ametis70/launchscope/server/internal/events"
	"github.com/ametis70/launchscope/server/internal/process"
)

func main() {
	log := slog.New(slog.NewTextHandler(os.Stderr, &slog.HandlerOptions{
		Level: slog.LevelInfo,
	}))

	// Config ($XDG_CONFIG_HOME/launchscoped/config.json)
	cfgDir, err := config.EnsureConfigDir()
	if err != nil {
		log.Error("cannot determine config directory", "err", err)
		os.Exit(1)
	}

	cfgLoader := config.NewLoader(cfgDir)
	cfg, err := cfgLoader.Load()
	if err != nil {
		log.Error("failed to load config", "dir", cfgDir, "err", err)
		os.Exit(1)
	}
	log.Info("config loaded",
		"dir", cfgDir,
		"api.port", cfg.API.Port,
		"cec.enabled", cfg.CEC.Enabled,
	)

	// Apps ($XDG_CONFIG_HOME/launchscoped/apps.json)
	appsLoader := apps.NewLoader(cfgDir)
	if _, err := appsLoader.Load(); err != nil {
		log.Error("failed to load apps", "dir", cfgDir, "err", err)
		os.Exit(1)
	}
	for _, a := range appsLoader.Current() {
		log.Info("app registered",
			"id", a.ID,
			"name", a.Name,
			"exec", a.Exec,
			"gamescope", a.Gamescope.Enabled,
		)
	}

	// Component-scoped loggers — filter at runtime with e.g.:
	//   journalctl -u launchscoped | grep component=api
	apiLog     := log.With("component", "api")
	processLog := log.With("component", "process")
	audioLog   := log.With("component", "audio")

	// Event bus
	bus := events.NewBus()

	// Audio monitor — runs for the lifetime of the process.
	audio.StartMonitor(context.Background(), time.Second, bus, audioLog)

	// Process manager
	launchscopeBin := os.Getenv("LAUNCHSCOPE_BIN")
	if launchscopeBin == "" {
		launchscopeBin = "launchscope"
	}

	mgr := process.NewManager(appsLoader, launchscopeBin, bus, processLog)
	mgr.Start()

	// HTTP server
	router := api.NewRouter(mgr, cfgLoader, appsLoader, bus, apiLog)
	addr := fmt.Sprintf(":%d", cfg.API.Port)
	log.Info("listening", "addr", addr)

	if err := http.ListenAndServe(addr, router); err != nil {
		log.Error("server error", "err", err)
		os.Exit(1)
	}
}
