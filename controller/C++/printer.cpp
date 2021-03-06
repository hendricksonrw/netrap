#include "printer.hpp"

#include <cstdio>
#include <cstring>

namespace C {
	#include <unistd.h>
	#include <sys/types.h>
	#include <sys/stat.h>
	#include <fcntl.h>

	extern "C" int printf(const char *format, ...);
}

#include "gcode.hpp"

std::list<Printer *> Printer::allprinters;
int Printer::allprinters_count;

Printer::Printer() {
	Socket::_fd = -1;
	init();
}

Printer::Printer(int fd) {
	Socket::open(fd);
	init();
}

Printer::Printer(char *port, int baud) {
	open(port, baud);
	init();
}

Printer::~Printer() {
	close();
	allprinters.remove(this);
	allprinters_count--;
}

char *Printer::name() {
	return _name;
}

void Printer::setname(char *newname) {
	free(_name);
	int l = strlen(newname);
	_name = (char *) malloc(l);
	memcpy(_name, newname, l);
}

int Printer::open(char *port, int baud) {
	_fd = open(port, O_RDWR | O_NOCTTY | O_NONBLOCK);
	if (_fd != -1) {
		return Socket::open(_fd);
	}
	return _fd;
}

void Printer::init() {
	allprinters.push_back(this);
	allprinters_count++;

	_name = (char *) malloc(sizeof(void *) * 2 + 3);
	C::printf("%d chars in name %s\n", snprintf(_name, sizeof(void *) * 2 + 3, "%p", this), this->name());

	capabilities["material"] = "PLA";
	capabilities["diameter"] = "3.0";
	capabilities["fan"] = "true";

	properties["position.X"] = "0";
	properties["position.Y"] = "0";
	properties["position.Z"] = "0";
	properties["position.E"] = "0";
	properties["position.F"] = "0";
	properties["target.X"] = "0";
	properties["target.Y"] = "0";
	properties["target.Z"] = "0";
	properties["target.E"] = "0";
	properties["target.F"] = "0";
	properties["temperature.hotend"] = "0";
	properties["temperature.hotend.target"] = "0";
	properties["temperature.bed"] = "0";
	properties["temperature.bed.target"] = "0";
	properties["fanspeed"] = "0";

	queuemanager.setDrain(this);
	if (_fd >= 0) {
		write("M115\n", 5);
		write("M114\n", 5);
		write("M105\n", 5);
	}
}

int Printer::write(string str) {
	return write(str.c_str(), str.length());
}

int Printer::write(const char *str, int len) {
	float words[32];
	uint32_t seen;
	// TODO: extract target properties from outgoing commands
	seen = Gcode::parse(str, len, words);
	return Socket::write(str, len);
}

int Printer::write(Socket *respondent, const char *str, int len) {
	this->respondent = respondent;
	return write(str, len);
}

int Printer::read(char *buf, int buflen) {
	int r = Socket::read(buf, buflen);
	// TODO: extract properties from replies
	if (respondent) {
		respondent->write(buf, buflen);
	}
	return r;
}

int Printer::printercount() {
	return allprinters_count;
}
