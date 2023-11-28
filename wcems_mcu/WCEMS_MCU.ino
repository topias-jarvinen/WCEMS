// Included libraries. Licenses are listed in the license file.
#include <SPI.h>
#include <AD5663_SPI.h>
#include <ADS1118_nrf52.h>
#include <MAX395_SPI.h>
#include <Adafruit_TinyUSB.h>
#include <bluefruit.h>

// BLE Services
BLEDfu  bledfu;  // OTA DFU service
BLEDis  bledis;  // device information
BLEUart bleuart; // uart over ble
BLEBas  blebas;  // battery

// Defining the SPI pins + reference voltage enable pin
const int DAC_CS_pin = 15;
const int ADC_CS_pin = 6;
const int SWITCHER_CS_pin = 13;
const int VREF_EN_pin = 9;

// Instancing component classes
SWITCHER switcher(SWITCHER_CS_pin);
AD5663 dac(DAC_CS_pin);
ADS1118 adc(ADC_CS_pin);

// Counters for measurement timing
unsigned long previousMillis;
unsigned long currentMillis;
const unsigned int sampleRate = 5; //200 Hz sampling rate for DAC, 20 Hz samplerate for ADC with by 10

// General constants
const long midV = 32768; // Digital ground at midpoint, also voltage for initalization
uint8_t switcherByte = 0x81; //Variable byte for switcher control. Default state: Amp=1k, everything disconnected, bypass enabled. 
  // Respective bits: 0-3 = amplification from 1k->1M. 4 = connect WE, 5 = connect DAC output to CE, 6 = connect RE+CE (two-probe measurement), 7 = Bypass 1k resistor in CE (default operation)
int measurementType = 1; //1 for CV, others to be implemented later
int electrodeConfig = 3; //2/3 electrode configuration, default = 3

// Constants for CV parameters
int amp = 1; // 1=1k, 2=10k, 3=100k, 4=1M, 1k as default, 1mA=>1V in transimpedance amplifier
int scanRate = 0; // Scanrate in mV
int startV = 0;  // Starting voltage in mV
int stopV = 0; // Voltage limit in mV
int cycles = 0; // Number of CV cycles
int resCE = 0; // Counter electrode resistor

// Serial parsing variables
const byte numChars = 32;
char receivedChars[numChars];
char tempChars[numChars];
boolean newData = false;

void setup() {
  // MAX395 switch initialization
  pinMode(SWITCHER_CS_pin, OUTPUT);
  switcher.init();
  switcher.write(switcherByte);

  // DAC initialization
  pinMode(DAC_CS_pin, OUTPUT);
  dac.init();
  dac.write(CHN_1,midV); //As default, set DAC output to midpoint (virtual ground)
  dac.write(CHN_2,midV); //Set up the virtual ground to channel 2

  // ADC initialization
  pinMode(ADC_CS_pin, OUTPUT);
  adc.begin();
  adc.setSamplingRate(adc.RATE_860SPS); //Could be lowered with asynhcronous ADC conversion
  adc.setInputSelected(adc.AIN_2); //ADC inputs: 0=VGND, 1=raw output, 2=LP filtered output, 3=DAC output (voltage ramp)
  adc.setFullScaleRange(adc.FSR_2048); //set range to 0 to 4.096 V to cover the full 3V operating voltage
  adc.setContinuousMode(); //Continous measuring

  Serial.begin(115200); //Keep for USB debugging

  // BLE initialization
  Bluefruit.autoConnLed(true);
  Bluefruit.configPrphBandwidth(BANDWIDTH_MAX);
  Bluefruit.begin();
  Bluefruit.setTxPower(4);
  Bluefruit.Periph.setConnectCallback(connect_callback);
  Bluefruit.Periph.setDisconnectCallback(disconnect_callback);
  bledfu.begin();

  // Configure and Start Device Information Service
  bledis.setManufacturer("Adafruit Industries");
  bledis.setModel("Bluefruit Feather52");
  bledis.begin();

  // Configure and Start BLE Uart Service
  bleuart.begin();

  // Start BLE Battery Service
  blebas.begin();
  blebas.write(100);

  // Set up and start advertising device
  startAdv();
}

void loop() { // Basic operating loop, returns to awaiting next measurement from Android device
  receive_bleuart();
  if (newData == true) { // If data received, execute measurement according to the parameters
    strcpy(tempChars, receivedChars); //Copy command for parsing
    parseCommand(); // Parse received data into measurement parameters
    showCommand(); // For debugging purposes
    newData = false; // Set flag to receive after measurement 
    Serial.println("Starting a CV measurement..."); // Debug
    CV(startV,stopV,scanRate,cycles,amp,electrodeConfig,resCE); // Run CV measurement with given parameters
  }
}


void CV(int startV, int stopV, int scanRate, int cycles, int amp, int electrodeConfig, int resCE){
  int vDac = 0; // raw DAC output value
  int vOut = 0; // DAC output in mV
  float vAdc = 0; // raw ADC input value
  String dataString = ""; // String for bleuart data throughput

  int mVRange = stopV-startV; // Total CV range
  int totalSteps = 200*mVRange/scanRate; // Total number of voltage steps required between voltage points, calculated as:
    // Refresh rate (200s^-1) * range in mV / scanRate (mV*s^-1)
  float voltageStep = (65536.0*float(mVRange))/(3000.0*float(totalSteps));
    // Single voltagestep defined by the total amount of steps and voltage range
  int initialV = midV - startV*65536/3000; // Starting point for DAC

  int j = 0; // Counter for CV loops
  int i = 0; // Counter for individual ramps
  int k = 1; // Index for datapoints

  SetSwitcher(amp,electrodeConfig,resCE); // Setting the measurement up with switcher

  for(i=1;i<=cycles;i++){
    j=0;
    vDac = initialV; // Begin loop from startV
    dac.write(CHN_1,vDac);
    while(j<=totalSteps){ // Go through voltagesteps
      currentMillis = millis();
      if(currentMillis - previousMillis >= sampleRate) { // Wait until 5 ms has occurred, then measure ADC and set next value
        previousMillis = currentMillis;
        if(j % 10 == 0){ // ADC samplerate 20 Hz
        vAdc = adc.getMilliVolts(); // Get ADC value
        vOut = (midV-vDac)*3000/65536; // Calculate current vOut as mV
        dataString += String(k);
        dataString += ",";
        dataString += String(vOut);
        dataString += ",";
        dataString += String(vAdc);
        bleuart.print(dataString);
        dataString = ""; // Clear datastring
        k++;
        }
        j++; 
        vDac = initialV - j*voltageStep; // Set next voltagestep
        dac.write(CHN_1,vDac);
      }        
    }
    // Record the peak value
    k++;
    vAdc = adc.getMilliVolts();
    dataString += String(k);
    dataString += ",";
    dataString += String(vOut);
    dataString += ",";
    dataString += String(vAdc);
    bleuart.print(dataString);
    dataString = "";

    while(j>=0){ // Return ramp
      currentMillis = millis();
      if(currentMillis - previousMillis >= sampleRate) {
        previousMillis = currentMillis;
        if(j % 10 == 0){
        vAdc = adc.getMilliVolts();
        vOut = (midV-vDac)*3000/65536;
        dataString += String(k);
        dataString += ",";
        dataString += String(vOut);
        dataString += ",";
        dataString += String(vAdc);
        bleuart.print(dataString);
        dataString = "";
        k++;
        }
        j--;   
        vDac = initialV - j*voltageStep;
        dac.write(CHN_1,vDac);     
      }
    }
    //Record last value
    k++;
    vAdc = adc.getMilliVolts();
    dataString += String(k);
    dataString += ",";
    dataString += String(vOut);
    dataString += ",";
    dataString += String(vAdc);
    bleuart.print(dataString);
    dataString = "";
  }

  switcherByte = 0x81; // Switch off everything, set default amplification
  switcher.write(switcherByte);
  
  bleuart.print("end");   // Sending end command via BLE
  Serial.println("System ready for the next measurement."); // Debug   
  return;
}

void SetSwitcher(int amp, int electrodeConfig, int resCE){

  switcherByte = 0x00; // Reset switcherbyte for input variables

  if(electrodeConfig == 2){ // set 2/3 electrodes
    switcherByte = switcherByte | 0x02; // Flip up bit 6 to connect RE+CE
  }

  if(resCE != 1){
    switcherByte = switcherByte | 0x01; // Flip up bit 7 to bypass CE resistor
  }

  switcherByte = switcherByte | 0x0C; // Flip up bit 4 and 5 to connect WE and DAC output

  switch(amp){ // Set amplification, 1k/10k/100k/1M, default as 1k
    case 1: switcherByte = switcherByte | 0x80;
      break;
    case 2: switcherByte = switcherByte | 0x40;
      break;
    case 3: switcherByte = switcherByte | 0x20;
      break;
    case 4: switcherByte = switcherByte | 0x10;
      break;
    default: switcherByte = switcherByte | 0x80;    
    }
    
  // Debug
  Serial.print("Switcherbyte command:");
  Serial.print(String(switcherByte)); 

  switcher.write(switcherByte); //Execute switch commands
  return;
}

void receive_bleuart() { //Serial parsing operations adapted from https://forum.arduino.cc/t/serial-input-basics-updated/382007
  static boolean recvInProgress = false;
  static byte ndx = 0;
  char startMarker = '<';
  char endMarker = '>';
  char rc;

  while (bleuart.available() > 0 && newData == false) {
    rc = bleuart.read();
    if (recvInProgress == true) {
      if (rc != endMarker) {
        receivedChars[ndx] = rc;
        ndx++;
        if (ndx >= numChars) {
          ndx = numChars - 1;
        }
      }
      else {
        receivedChars[ndx] = '\0';
        recvInProgress = false;
        ndx = 0;
        newData = true;
      }
    }
    else if (rc == startMarker) {
      recvInProgress = true;
    }
  }
}

void parseCommand() { //Split serial input into variables
  char * strtokIndx;

  strtokIndx = strtok(tempChars,","); //Get Electrode config (2/3)
  electrodeConfig = atoi(strtokIndx);
  strtokIndx = strtok(NULL, ",");
  startV = atoi(strtokIndx);
  strtokIndx = strtok(NULL, ",");
  stopV = atoi(strtokIndx);
  strtokIndx = strtok(NULL, ",");
  scanRate = atoi(strtokIndx);    
  strtokIndx = strtok(NULL, ",");
  cycles = atoi(strtokIndx);
  strtokIndx = strtok(NULL, ",");
  amp = atoi(strtokIndx);
  strtokIndx = strtok(NULL, ",");
  resCE = atoi(strtokIndx);
}

void showCommand() {
  Serial.print("Electrodes: ");
  Serial.println(electrodeConfig);
  Serial.print("Starting voltage in mV: ");
  Serial.println(startV);
  Serial.print("Stopping voltage in mV: ");
  Serial.println(stopV);
  Serial.print("Scanrate: ");
  Serial.println(scanRate);
  Serial.print("Number of cycles: ");
  Serial.println(cycles);
  Serial.print("Amplification: ");
  Serial.println(amp);
  Serial.print("CE resistor: ");
  Serial.println(resCE);
} 

void startAdv(void)
{
  // Advertising packet
  Bluefruit.Advertising.addFlags(BLE_GAP_ADV_FLAGS_LE_ONLY_GENERAL_DISC_MODE);
  Bluefruit.Advertising.addTxPower();

  // Include bleuart 128-bit uuid
  Bluefruit.Advertising.addService(bleuart);

  // Secondary Scan Response packet (optional)
  // Since there is no room for 'Name' in Advertising packet
  Bluefruit.ScanResponse.addName();
  
  /* Start Advertising
   * - Enable auto advertising if disconnected
   * - Interval:  fast mode = 20 ms, slow mode = 152.5 ms
   * - Timeout for fast mode is 30 seconds
   * - Start(timeout) with timeout = 0 will advertise forever (until connected)
   * 
   * For recommended advertising interval
   * https://developer.apple.com/library/content/qa/qa1931/_index.html   
   */
  Bluefruit.Advertising.restartOnDisconnect(true);
  Bluefruit.Advertising.setInterval(32, 244);    // in unit of 0.625 ms
  Bluefruit.Advertising.setFastTimeout(30);      // number of seconds in fast mode
  Bluefruit.Advertising.start(0);                // 0 = Don't stop advertising after n seconds
  
}

// callback invoked when central connects
void connect_callback(uint16_t conn_handle)
{
  // Get the reference to current connection
  BLEConnection* connection = Bluefruit.Connection(conn_handle);

  char central_name[32] = { 0 };
  connection->getPeerName(central_name, sizeof(central_name));

  Serial.print("Connected to ");
  Serial.println(central_name);
}

/**
 * Callback invoked when a connection is dropped
 * @param conn_handle connection where this event happens
 * @param reason is a BLE_HCI_STATUS_CODE which can be found in ble_hci.h
 */
void disconnect_callback(uint16_t conn_handle, uint8_t reason)
{
  (void) conn_handle;
  (void) reason;

  Serial.println();
  Serial.print("Disconnected, reason = 0x"); Serial.println(reason, HEX);
}
