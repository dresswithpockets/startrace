out/trace.exe: src/*.odin
	odin build src -build-mode:exe -debug -out:out/trace.exe

out/trace-release.exe: src/*.odin
	odin build src -build-mode:exe -o:speed -out:out/trace-release.exe

rundebug: out/trace.exe
	out/trace.exe

runrelease: out/trace-release.exe
	out/trace-release.exe

.PHONY: clean

clean:
	rm out/*
