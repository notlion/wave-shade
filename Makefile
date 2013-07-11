lib/embr/build/embr.js:
	cd ./lib/embr/ && make

compile: lib/embr/build/embr.js
	./node_modules/coffee-script/bin/coffee -bw -o ./build -c ./src

clean:
	rm -rf ./build
	cd ./lib/embr/ && make clean
