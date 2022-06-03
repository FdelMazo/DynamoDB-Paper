all:
	pandoc -t revealjs -s -o index.html header.yaml README.md -V revealjs-url=./reveal.js --slide-level=2 -V theme=simple
