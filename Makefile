PREFIX ?= ~/.local

superbright: superbright.swift
	swiftc -cross-module-optimization -O -parse-as-library -o $@ $<

install: superbright
	install -m 0755 superbright $(PREFIX)/bin/superbright

uninstall:
	rm -f $(PREFIX)/bin/superbright

clean:
	rm -f superbright

.PHONY: install uninstall clean
