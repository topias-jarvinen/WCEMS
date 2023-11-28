#ifndef MAX395_SPI
#define MAX395_SPI

#include "Arduino.h"

/* static const byte switcher_set = B00011000;
static const byte switcher_off	= B00000000;
static const byte RESET = B00101111; */

class SWITCHER
{
	private:
		byte _SSpin;
	public:
		SWITCHER(byte SSpin);
		void init(void);
		void write(byte switcher_set);
};

#endif