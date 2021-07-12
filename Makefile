all: lint test

lint:
	@luacheck --std=luajit+busted lib spec

test:
	@busted --lua=luajit

coverage: clean test
	@luacov
	@tail -n 9 luacov.report.out

clean:
	@rm -f luacov.report.out luacov.stats.out
