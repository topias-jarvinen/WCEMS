#include "MAX395_SPI.h"
#include <SPI.h>

SWITCHER::SWITCHER(byte SSpin)
{
	_SSpin = SSpin;
}

void SWITCHER::init(void)
{
	pinMode(_SSpin, OUTPUT);
	SPI.beginTransaction(SPISettings(2000000, MSBFIRST, SPI_MODE0));
	SPI.begin();
	delayMicroseconds(1);
	digitalWrite(_SSpin, LOW);
	SPI.transfer(0b00000000);
	delayMicroseconds(1);
	digitalWrite(_SSpin, HIGH);
	SPI.endTransaction();
}

void SWITCHER::write(byte switcher_set)
{	SPI.beginTransaction(SPISettings(2000000, MSBFIRST, SPI_MODE0)); // SET CORRECT SPI (INCLUDING FREQUENCY)
	delayMicroseconds(1);
	digitalWrite(_SSpin, LOW);
	SPI.transfer(switcher_set);
	delayMicroseconds(1);
	digitalWrite(_SSpin, HIGH);
	SPI.endTransaction();
}