test:
	@busted --lua=luajit

coverage: test
	@luacov
	@tail -n 9 luacov.report.out

clean:
	@rm -f luacov.report.out luacov.stats.out
