.PHONY: test

TESTS = test/*.coffee

test:
	mocha --compilers coffee:coffee-script $(TESTS)

