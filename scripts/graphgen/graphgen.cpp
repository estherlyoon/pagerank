#include <stdio.h>
#include <stdlib.h>
#include <stdint.h>
#include <vector>
#include <unordered_set>

uint64_t separator = 0;

void update_separator(FILE* fp) {
	separator++;
	if (separator % 8 == 0)
		fprintf(fp, "\n");
}

void write_hex(FILE* fp, uint64_t n) {
	fprintf(fp, "%016X", (uint32_t)n);
}

int main(int argc, char* argv[]) {
	char* p;
	uint64_t vertices = strtoul(argv[1], &p, 10);
	uint64_t edges = strtoul(argv[2], &p, 10);
	FILE* fp = fopen("mem_init.hex", "w+");

	printf("%lu vertices, %lu edges\n", vertices, edges);

	std::vector<std::unordered_set<uint64_t>> graph(vertices, std::unordered_set<uint64_t>(0));
	std::vector<uint64_t> outdeg(vertices);

	// generate graph
	uint64_t e = 0;
	while (e < edges) {
		uint64_t src = rand() % vertices;
		uint64_t dest = rand() % vertices;
		if (src != dest && !graph[dest].count(src)) {
			e++;
			graph[dest].insert(src);
			outdeg[src]++;
		}
	}

	uint64_t offset = 0;

	for (uint64_t i = 0; i < vertices; i++) {
		write_hex(fp, offset);
		update_separator(fp);
		offset += graph[i].size();
		write_hex(fp, outdeg[i]);
		update_separator(fp);
	}

	// axi-align file contents
	while (separator % 8) {
		write_hex(fp, 0);
		update_separator(fp);
	}

	// print in-edge vertices to file, updating separator
	for (uint64_t i = 0; i < vertices; i++) {
		//printf("V%lu, out-degree = %lu\n", i, outdeg[i]);
		for (const auto& elem: graph[i]) {
			//printf("\t%lu\n", elem);
			write_hex(fp, elem);
			update_separator(fp);
		}
	}

	// write space, update separator
	for (uint64_t i = 0; i < vertices*2; i++) {
		write_hex(fp, 0);
		update_separator(fp);
	}

	while (separator % 8) {
		write_hex(fp, 0);
		separator++;
	}

	fclose(fp);

	// write parameters to file
	FILE* f = fopen("params.txt", "w+");

	uint64_t vbytes = 16 * vertices;
	uint64_t ieaddr = (vbytes % 64) == 0 ? vbytes : vbytes + (64 - (vbytes % 64));

	fprintf(f, "n_vert: %d\n", vertices);
	fprintf(f, "n_inedges: %d\n", edges);
	fprintf(f, "vaddr: 0\n");
	fprintf(f, "ieaddr: %d\n", ieaddr);
	fprintf(f, "waddr0: %d\n", ieaddr + 8*edges);
	fprintf(f, "waddr1: %d\n", ieaddr + 8*vertices);
	fclose(f);

	return 0;
}
