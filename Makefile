.PHONY: test

TESTS = test/*.coffee

test:
	./node_modules/mocha/bin/mocha $(TESTS)

