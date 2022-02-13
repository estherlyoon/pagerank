#include <stdio.h>
#include <stdlib.h>
#include <stdint.h>
#include <vector>

uint64_t separator = 0;

void update_separator(FILE* fp) {
	separator++;
	if (separator % 8 == 0)
		fprintf(fp, "\n");
}

void write_hex(FILE* fp, uint64_t n) {

	if (n > 0) {

	} else if (n == 0) {

	}

	fprintf(fp, "%016X", (uint32_t)n);
}

int main(int argc, char* argv[]) {
	char* p;
	uint64_t vertices = strtoul(argv[1], &p, 10);
	uint64_t edges = strtoul(argv[2], &p, 10);
	FILE* fp = fopen("mem_init.hex", "w+");

	printf("%lu vertices, %lu edges\n", vertices, edges);

	std::vector<std::vector<uint64_t>> graph(vertices, std::vector<uint64_t>(0));
	std::vector<uint64_t> outdeg(vertices);

	// generate graph
	uint64_t e = 0;
	while (e < edges) {
		uint64_t src = rand() % vertices;
		uint64_t dest = rand() % vertices;
		e++;
		graph[dest].push_back(src);
		outdeg[src]++;
		if (e % 1000000 == 0)
			printf("edge %lu/%lu\n", e, edges);
	}

	printf("done generating graph\n");

	uint64_t offset = 0;

	for (uint64_t i = 0; i < vertices; i++) {
		write_hex(fp, offset);
		update_separator(fp);
		offset += graph[i].size();
		write_hex(fp, outdeg[i]);
		update_separator(fp);
		if (i % 100000 == 0)
			printf("vert %lu/%lu\n", i, vertices);
	}

	printf("wrote vertices\n");

	// axi-align file contents
	while (separator % 8) {
		write_hex(fp, 0);
		update_separator(fp);
	}

	// print in-vertices to file, updating separator
	for (uint64_t i = 0; i < vertices; i++) {
		//printf("V%lu, out-degree = %lu\n", i, outdeg[i]);
		for (const auto& elem: graph[i]) {
			//printf("\t%lu\n", elem);
			write_hex(fp, elem);
			update_separator(fp);
		}
		if (i % 1000000 == 0)
			printf("edgevert %lu/%lu\n", i, vertices);
	}

	printf("wrote edges\n");

	// write space, update separator
	for (uint64_t i = 0; i < vertices*2; i++) {
		write_hex(fp, 0);
		update_separator(fp);
		if (i % 20000 == 0)
			printf("space %lu/%lu\n", i, vertices*2);
	}
	printf("wrote write space\n");

	while (separator % 8) {
		write_hex(fp, 0);
		separator++;
	}

	fclose(fp);

	return 0;
}
