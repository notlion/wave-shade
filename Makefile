all: build/bundle.js

build/main.js:
	node_modules/coffee-script/bin/coffee -b -j build/main.js -c ./src

build/bundle.js: build/main.js
	node_modules/browserify/bin/cmd.js build/main.js -o build/bundle.js

clean:
	rm -rf ./build

run: all
	python -m SimpleHTTPServer 3000
