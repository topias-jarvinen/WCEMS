#include "AD5663_SPI.h"
#include <SPI.h>

AD5663::AD5663(byte SSpin)
{
	_SSpin = SSpin;
}

void AD5663::init(void)
{
	pinMode(_SSpin, OUTPUT);
	SPI.beginTransaction(SPISettings(16000000, MSBFIRST, SPI_MODE2));
	SPI.begin();
	delayMicroseconds(1);
	digitalWrite(_SSpin, LOW);
	SPI.transfer(0b0010100);
	SPI.transfer(0b00000000);
	SPI.transfer(0b00000001);
	delayMicroseconds(1);
	digitalWrite(_SSpin, HIGH);
}

void AD5663::write(byte DAC_CMD, uint16_t dacValue)
{	digitalWrite(_SSpin, LOW);
	byte highByte = dacValue >> 8;
	byte lowByte = dacValue;
	SPI.beginTransaction(SPISettings(16000000, MSBFIRST, SPI_MODE2));
	SPI.transfer(DAC_CMD);
	SPI.transfer(highByte);
	SPI.transfer(lowByte);
	delayMicroseconds(1);
	digitalWrite(_SSpin, HIGH);	
	SPI.endTransaction();
}