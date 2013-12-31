.PHONY: test

TESTS = test/*.coffee

test:
	./node_modules/.bin/mocha --compilers coffee:coffee-script $(TESTS)

