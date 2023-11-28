#ifndef AD5663_SPI
#define AD5663_SPI

#include "Arduino.h"

static const byte CHN_1  	= B00011000;
static const byte CHN_2  	= B00011001;
static const byte CHN_ALL  	= B11111000;
static const byte RESET = B00101111;

class AD5663
{
	private:
		byte _SSpin;
	public:
		AD5663(byte SSpin);
		void init(void);
		void write(byte DAC_CHN, uint16_t dacValue);
};

#endif