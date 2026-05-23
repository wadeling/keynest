.PHONY: app run build clean

app:
	./Scripts/package-app.sh

run:
	swift run

build:
	swift build

clean:
	swift package clean
