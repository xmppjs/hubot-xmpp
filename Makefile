.PHONY: test release bump-version

REMOTE=origin

TESTS = test/*.js

test:
	./node_modules/.bin/mocha $(TESTS)

release: bump-version
	@echo "Tagging $(VERSION)"
	git tag -s v$(VERSION) -m "Hubot XMPP $(VERSION)\n$(MESSAGE)"
	git push $(REMOTE)
	git push $(REMOTE) --tags

bump-version: guard-VERSION
	@echo "Update package.json to $(VERSION)"
	# Work around sed being bad.
	mv package.json package.json.old
	cat package.json.old | sed s'/^[ ]*"version": "[0-9]\.[0-9]\.[0-9]".*/  "version": "$(VERSION)",/' > package.json
	rm package.json.old
	git add package.json
	git commit -m "Update version number to $(VERSION)"

# Utility target for checking required parameters
guard-%:
	@if [ "$($*)" = '' ]; then \
		echo "Missing required $* variable."; \
		exit 1; \
	fi;
