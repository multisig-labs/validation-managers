# Autoload a .env if one exists
set dotenv-load

# VERSION := `grep "const Version " pkg/version/version.go | sed -E 's/.*"(.+)"$$/\1/'`
# GIT_COMMIT := `git rev-parse HEAD`
# BUILD_DATE := `date '+%Y-%m-%d'`
# VERSION_PATH := "github.com/multisig-labs/panopticon/pkg/version"
# LDFLAGS := "-s -w " + "-X " + VERSION_PATH + ".BuildDate=" + BUILD_DATE + " -X " + VERSION_PATH + ".Version=" + VERSION + " -X " + VERSION_PATH + ".GitCommit=" + GIT_COMMIT

# Print out some help
default:
	@just --list --unsorted

setup:
	git submodule update --init --recursive

