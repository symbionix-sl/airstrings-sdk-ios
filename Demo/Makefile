.PHONY: setup project config seed open clean

# Full setup: generate config, create Xcode project, seed data, open Xcode
setup: config project seed open

# Generate Xcode project from project.yml
project:
	xcodegen generate

# Extract public key → DemoConfig.generated.swift
config:
	bash generate-config.sh

# Seed demo strings and publish bundles via the API
seed:
	bash seed.sh

# Generate project and open in Xcode
open: project
	open *.xcodeproj

# Remove generated Xcode project
clean:
	rm -rf *.xcodeproj
