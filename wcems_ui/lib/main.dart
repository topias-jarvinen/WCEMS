// BLE-related libraries cited in the LICENSE file.

// Import the necessary libraries. Notably flutter_blue_plus for BLE comms, and charts/sparkcharts for data representation.
import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:syncfusion_flutter_charts/charts.dart';
import 'widgets.dart';

// Import libraries for saving to file.
import 'package:to_csv/to_csv.dart' as exportCSV;

//ID's for bleuart
Guid _UART_GUID = Guid("6E400001-B5A3-F393-E0A9-E50E24DCCA9E");
Guid _UART_GUID_RX = Guid("6E400002-B5A3-F393-E0A9-E50E24DCCA9E");
Guid _UART_GUID_TX = Guid("6E400003-B5A3-F393-E0A9-E50E24DCCA9E");

final snackBarKeyA = GlobalKey<ScaffoldMessengerState>();
final snackBarKeyB = GlobalKey<ScaffoldMessengerState>();
final snackBarKeyC = GlobalKey<ScaffoldMessengerState>();
final Map<DeviceIdentifier, ValueNotifier<bool>> isConnectingOrDisconnecting = {};

void main() {
  if (Platform.isAndroid) {
    WidgetsFlutterBinding.ensureInitialized(); //Securing device permissions for accessing location, storage and bluetooth components.
    [
      Permission.location,
      Permission.storage,
      Permission.bluetooth,
      Permission.bluetoothConnect,
      Permission.bluetoothScan
    ].request().then((status) {
      runApp(const FlutterBlueApp());
    });
  } else {
    runApp(const FlutterBlueApp());
  }
}

class BluetoothAdapterStateObserver extends NavigatorObserver { //Basic screens (from flutter_blue_plus)
  StreamSubscription<BluetoothAdapterState>? _btStateSubscription;

  @override
  void didPush(Route route, Route? previousRoute) {
    super.didPush(route, previousRoute);
    if (route.settings.name == '/deviceScreen') {
      // Start listening to Bluetooth state changes when a new route is pushed
      _btStateSubscription ??= FlutterBluePlus.adapterState.listen((state) {
        if (state != BluetoothAdapterState.on) {
          // Pop the current route if Bluetooth is off
          navigator?.pop();
        }
      });
    }
  }

  @override
  void didPop(Route route, Route? previousRoute) {
    super.didPop(route, previousRoute);
    // Cancel the subscription when the route is popped
    _btStateSubscription?.cancel();
    _btStateSubscription = null;
  }
}

class FlutterBlueApp extends StatelessWidget {  //Initializing BLE adapter (from flutter_blue_plus)
  const FlutterBlueApp({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    sleep(const Duration(milliseconds: 100));
    return MaterialApp(
      color: Colors.lightBlue,
      home: StreamBuilder<BluetoothAdapterState>(
          stream: FlutterBluePlus.adapterState,
          initialData: BluetoothAdapterState.unknown,
          builder: (c, snapshot) {
            final adapterState = snapshot.data;
            if (adapterState == BluetoothAdapterState.on) {
              return const FindDevicesScreen();
            } else {
              FlutterBluePlus.stopScan();
              return BluetoothOffScreen(adapterState: adapterState);
            }
          }),
      navigatorObservers: [BluetoothAdapterStateObserver()],
    );
  }
}

class BluetoothOffScreen extends StatelessWidget {  //Monitoring BLE adapter state (from flutter_blue_plus)
  const BluetoothOffScreen({Key? key, this.adapterState}) : super(key: key);

  final BluetoothAdapterState? adapterState;

  @override
  Widget build(BuildContext context) {
    return ScaffoldMessenger(
      key: snackBarKeyA,
      child: Scaffold(
        backgroundColor: Colors.lightBlue,
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              const Icon(
                Icons.bluetooth_disabled,
                size: 200.0,
                color: Colors.white54,
              ),
              Text(
                'Bluetooth Adapter is ${adapterState != null ? adapterState.toString().split(".").last : 'not available'}.',
                style: Theme.of(context).primaryTextTheme.titleSmall?.copyWith(color: Colors.white),
              ),
              if (Platform.isAndroid)
                ElevatedButton(
                  child: const Text('TURN ON'),
                  onPressed: () async {
                    try {
                      if (Platform.isAndroid) {
                        await FlutterBluePlus.turnOn();
                      }
                    } catch (e) {
                      final snackBar = snackBarFail(prettyException("Error Turning On:", e));
                      snackBarKeyA.currentState?.removeCurrentSnackBar();
                      snackBarKeyA.currentState?.showSnackBar(snackBar);
                    }
                  },
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class FindDevicesScreen extends StatefulWidget {  //Sligthly modified screen to find and connect to BLE devices (from flutter_blue_plus)
  const FindDevicesScreen({Key? key}) : super(key: key);

  @override
  State<FindDevicesScreen> createState() => _FindDevicesScreenState();
}

class _FindDevicesScreenState extends State<FindDevicesScreen> {
  @override
  Widget build(BuildContext context) {
    return ScaffoldMessenger(
      key: snackBarKeyB,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Find Devices'),
        ),
        body: RefreshIndicator(
          onRefresh: () {
            setState(() {}); // force refresh of connectedSystemDevices
            if (FlutterBluePlus.isScanningNow == false) {
              FlutterBluePlus.startScan(timeout: const Duration(seconds: 15), androidUsesFineLocation: false);
            }
            return Future.delayed(const Duration(milliseconds: 500)); // show refresh icon breifly
          },
          child: SingleChildScrollView(
            child: Column(
              children: <Widget>[
                StreamBuilder<List<BluetoothDevice>>(
                  stream: Stream.fromFuture(FlutterBluePlus.connectedSystemDevices),
                  initialData: const [],
                  builder: (c, snapshot) => Column(
                    children: (snapshot.data ?? [])
                        .map((d) => ListTile(
                              title: Text(d.localName),
                              subtitle: Text(d.remoteId.toString()),
                              trailing: StreamBuilder<BluetoothConnectionState>(
                                stream: d.connectionState,
                                initialData: BluetoothConnectionState.disconnected,
                                builder: (c, snapshot) {
                                  if (snapshot.data == BluetoothConnectionState.connected) {
                                    return ElevatedButton(
                                      child: const Text('OPEN'),
                                      onPressed: () => Navigator.of(context).push(MaterialPageRoute(
                                          builder: (context) => DeviceScreen(device: d),
                                          settings: const RouteSettings(name: '/deviceScreen'))),
                                    );
                                  }
                                  if (snapshot.data == BluetoothConnectionState.disconnected) {
                                    return ElevatedButton(
                                        child: const Text('CONNECT'),
                                        onPressed: () async {
                                          await d.connect(timeout: const Duration(seconds: 35)).catchError((e) {
                                            final snackBar = snackBarFail(prettyException("Connect Error:", e));
                                            snackBarKeyC.currentState?.removeCurrentSnackBar();
                                            snackBarKeyC.currentState?.showSnackBar(snackBar);
                                            }).then((v) {
                                              isConnectingOrDisconnecting[d.remoteId] ??= ValueNotifier(false);
                                              isConnectingOrDisconnecting[d.remoteId]!.value = false;
                                          });
                                          var srvs = await d.discoverServices();
                                          try {
                                            var mtu = await d.requestMtu(223);
                                            print("mtu: " + mtu.toString());
                                            print("services:" + srvs.toString());
                                            final snackBar = snackBarGood("Request Mtu: Success");
                                            snackBarKeyC.currentState?.removeCurrentSnackBar();
                                            snackBarKeyC.currentState?.showSnackBar(snackBar);
                                            Navigator.of(context).push(MaterialPageRoute(
                                            builder: (context) {
                                              isConnectingOrDisconnecting[d.remoteId] ??= ValueNotifier(true);
                                              isConnectingOrDisconnecting[d.remoteId]!.value = true;                                              
                                              try {
                                                final snackBar = snackBarGood("Discover Services: Success");
                                                snackBarKeyC.currentState?.removeCurrentSnackBar();
                                                snackBarKeyC.currentState?.showSnackBar(snackBar);
                                              } catch (e) {
                                                final snackBar = snackBarFail(prettyException("Discover Services Error:", e));
                                                snackBarKeyC.currentState?.removeCurrentSnackBar();
                                                snackBarKeyC.currentState?.showSnackBar(snackBar);
                                              }
                                              return DeviceScreen(device: d);
                                            },
                                            settings: const RouteSettings(name: '/deviceScreen')));
                                          } catch (e) {
                                            final snackBar = snackBarFail(prettyException("Change Mtu Error:", e));
                                            snackBarKeyC.currentState?.removeCurrentSnackBar();
                                            snackBarKeyC.currentState?.showSnackBar(snackBar);
                                          }
                                          
                                        });
                                  }
                                  return Text(snapshot.data.toString().toUpperCase().split('.')[1]);
                                },
                              ),
                            ))
                        .toList(),
                  ),
                ),
                StreamBuilder<List<ScanResult>>(
                  stream: FlutterBluePlus.scanResults,
                  initialData: const [],
                  builder: (c, snapshot) => Column(
                    children: (snapshot.data ?? [])
                        .map(
                          (r) => ScanResultTile(
                            result: r,
                            onTap: () async {
                              final d = r.device;
                                          await d.connect(timeout: const Duration(seconds: 35)).catchError((e) {
                                            final snackBar = snackBarFail(prettyException("Connect Error:", e));
                                            snackBarKeyC.currentState?.removeCurrentSnackBar();
                                            snackBarKeyC.currentState?.showSnackBar(snackBar);
                                            });
                                          var srvs = await d.discoverServices();
                                          try {
                                            var mtu = await d.requestMtu(223);
                                            print("mtu: " + mtu.toString());
                                            print("services:" + srvs.toString());
                                            final snackBar = snackBarGood("Request Mtu: Success");
                                            snackBarKeyC.currentState?.removeCurrentSnackBar();
                                            snackBarKeyC.currentState?.showSnackBar(snackBar);
                                            Navigator.of(context).push(MaterialPageRoute(
                                            builder: (context) {
                                              isConnectingOrDisconnecting[d.remoteId] ??= ValueNotifier(true);
                                              isConnectingOrDisconnecting[d.remoteId]!.value = true;                                              
                                              try {
                                                final snackBar = snackBarGood("Discover Services: Success");
                                                snackBarKeyC.currentState?.removeCurrentSnackBar();
                                                snackBarKeyC.currentState?.showSnackBar(snackBar);
                                              } catch (e) {
                                                final snackBar = snackBarFail(prettyException("Discover Services Error:", e));
                                                snackBarKeyC.currentState?.removeCurrentSnackBar();
                                                snackBarKeyC.currentState?.showSnackBar(snackBar);
                                              }
                                              return DeviceScreen(device: d);
                                            },
                                            settings: const RouteSettings(name: '/deviceScreen')));
                                          } catch (e) {
                                            final snackBar = snackBarFail(prettyException("Change Mtu Error:", e));
                                            snackBarKeyC.currentState?.removeCurrentSnackBar();
                                            snackBarKeyC.currentState?.showSnackBar(snackBar);
                                          }
                                          
                                        },
                          ),
                        )
                        .toList(),
                  ),
                ),
              ],
            ),
          ),
        ),
        floatingActionButton: StreamBuilder<bool>(
          stream: FlutterBluePlus.isScanning,
          initialData: false,
          builder: (c, snapshot) {
            if (snapshot.data ?? false) {
              return FloatingActionButton(
                onPressed: () async {
                  try {
                    FlutterBluePlus.stopScan();
                  } catch (e) {
                    final snackBar = snackBarFail(prettyException("Stop Scan Error:", e));
                    snackBarKeyB.currentState?.removeCurrentSnackBar();
                    snackBarKeyB.currentState?.showSnackBar(snackBar);
                  }
                },
                backgroundColor: Colors.red,
                child: const Icon(Icons.stop),
              );
            } else {
              return FloatingActionButton(
                  child: const Text("SCAN"),
                  onPressed: () async {
                    try {
                      if (FlutterBluePlus.isScanningNow == false) {
                        FlutterBluePlus.startScan(timeout: const Duration(seconds: 15), androidUsesFineLocation: false);
                      }
                    } catch (e) {
                      final snackBar = snackBarFail(prettyException("Start Scan Error:", e));
                      snackBarKeyB.currentState?.removeCurrentSnackBar();
                      snackBarKeyB.currentState?.showSnackBar(snackBar);
                    }
                    setState(() {}); // force refresh of connectedSystemDevices
                  });
            }
          },
        ),
      ),
    );
  }
}

class DeviceScreen extends StatefulWidget { //Screen for UI implementation after connecting (from flutter_blue_plus)
  final BluetoothDevice device;

  const DeviceScreen({Key? key, required this.device}) : super(key: key);

  @override
  State<DeviceScreen> createState() => _DeviceScreenState();
}

//Add fields for inputting measurement controls.
class _DeviceScreenState extends State<DeviceScreen> {
  List<MeasData> data_array = [];
  final TextEditingController electrodeController = TextEditingController(text: "3");
  final TextEditingController startVController = TextEditingController();
  final TextEditingController stopVController = TextEditingController();
  final TextEditingController scanRateController = TextEditingController();
  final TextEditingController cyclesController = TextEditingController();
  final TextEditingController ampController = TextEditingController(text: "1");
  final TextEditingController resistorController = TextEditingController(text: "0");

  void csvWrite() { //Function for file writing
    List<List<String>> listOfLists = []; //Outter List which contains the data List
    List<String> header = []; //Add headers to CSV
    header.add('Index');
    header.add('Voltage');
    header.add('Current');
    for(MeasData row in data_array) { //Copy each row from measurement data to listOfLists
      listOfLists.add([row.index.toString(),row.voltage.toString(),row.current.toString()]);
    }
    data_array = [];  //Reset data_array for next measurement
    exportCSV.myCSV(header, listOfLists); //Write listOfLists to .CSV file

  }

  @override
  Widget build(BuildContext context) {  //UI and logic for forming the measurement command string
    return ScaffoldMessenger(
      key: snackBarKeyC,
      child: Scaffold(
        appBar: AppBar(
          title: Text(widget.device.localName),
        ),
        body: SingleChildScrollView(
          child: Column(
            children: <Widget>[
              StreamBuilder<BluetoothConnectionState>(
                stream: widget.device.connectionState,
                initialData: BluetoothConnectionState.connecting,
                builder: (c, snapshot) => Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.all(8.0),
                      child: Text('${widget.device.remoteId}'),
                    ),
                    Row(
                      mainAxisSize: MainAxisSize.max,
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            snapshot.data == BluetoothConnectionState.connected
                                ? const Icon(Icons.bluetooth_connected)
                                : const Icon(Icons.bluetooth_disabled),
                            snapshot.data == BluetoothConnectionState.connected
                                ? StreamBuilder<int>(
                                    stream: rssiStream(maxItems: 1),
                                    builder: (context, snapshot) {
                                      return Text(snapshot.hasData ? '${snapshot.data}dBm' : '',
                                          style: Theme.of(context).textTheme.bodySmall);
                                    })
                                : Text('', style: Theme.of(context).textTheme.bodySmall),
                          ],
                        ),
                        Text('Device is ${snapshot.data.toString().split('.')[1]}.'),
                        StreamBuilder<int>(
                          stream: widget.device.mtu,
                          initialData: 0,
                          builder: (c, snapshot) => Column(
                            children: [
                              const Text('MTU Size'),
                              Text('${snapshot.data} bytes'),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              Padding(  //Setting electrode mode
                padding: const EdgeInsets.symmetric(horizontal : 20.0),
                child: Row(
                    children: [
                      Text("Electrode mode: "),
                      Spacer(),
                      Text("3"),
                      Switch(value: electrodeController.text == "2", onChanged: (bool newvalue){
                        electrodeController.text = newvalue ? "2" : "3";
                        setState(() {                    
                        });
                      }),
                      Text("2"),
                    ],
                  ),
              ),
              const Padding(padding: EdgeInsets.symmetric(vertical: 5)),
              Padding(  //Setting CE resistor
                padding: const EdgeInsets.symmetric(horizontal : 20.0),
                child: Row(
                    children: [
                      Text("Use 1k resistor at CE: "),
                      Spacer(),                      
                      Switch(value: resistorController.text == "1", onChanged: (bool newvalue){
                        resistorController.text = newvalue ? "1" : "0";
                        setState(() {                    
                        });
                      }),
                    ],
                  ),
              ),
              const Padding(padding: EdgeInsets.symmetric(vertical: 5)),
              TextField(  //Setting starting voltage value
                controller: startVController,
                keyboardType: TextInputType.numberWithOptions(signed:true),
                decoration: const InputDecoration(labelText: "V1 (mV)",
                  contentPadding: EdgeInsets.symmetric(horizontal: 5.0)
                ),
              ),
              const Padding(padding: EdgeInsets.symmetric(vertical: 5)),
              TextField(  //Setting upper voltage limit
                controller: stopVController,
                keyboardType: TextInputType.numberWithOptions(signed:true),
                decoration: const InputDecoration(labelText: "V2 (mV)",
                  contentPadding: EdgeInsets.symmetric(horizontal: 5.0)
                ),
              ),
              const Padding(padding: EdgeInsets.symmetric(vertical: 5)),
              TextField(  //Setting scanrate
                controller: scanRateController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: "Scan Rate (mV/s)",
                  contentPadding: EdgeInsets.symmetric(horizontal: 5.0)
                ),
              ),
              const Padding(padding: EdgeInsets.symmetric(vertical: 5)),
              TextField(  //Setting number of CV cycles
                controller: cyclesController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: "Cycles",
                  contentPadding: EdgeInsets.symmetric(horizontal: 5.0)
                ),
              ),
              const Padding(padding: EdgeInsets.symmetric(vertical: 5)),
              Padding(  //Setting amplification
                padding: const EdgeInsets.symmetric(horizontal : 20.0),
                child: Row(
                  mainAxisSize: MainAxisSize.max,
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text("Select current range: "),                      
                      DropdownMenu(dropdownMenuEntries: const [
                        DropdownMenuEntry(value: "1", label: "0.3 - 3 mA"),
                        DropdownMenuEntry(value: "2", label: "30 - 300 µA"),
                        DropdownMenuEntry(value: "3", label: "3-30 µA"),
                        DropdownMenuEntry(value: "4", label: "0.3 - 3 µA"),
                        ],
                        initialSelection: "1",
                        onSelected: (value) => ampController.text = value!
                        )
                    ],
                  ),
              ),
              const Padding(padding: EdgeInsets.symmetric(vertical: 5)),

              StreamBuilder<List<BluetoothService>>(
                stream: widget.device.servicesStream,
                initialData: const [], 
                builder: (c, snapshot) {
                  final services = snapshot.data?.where((serv) => serv.serviceUuid == _UART_GUID).toList();
                  if (services?.isNotEmpty ?? false) {
                    BluetoothService? s = services![0];
                    final List<BluetoothCharacteristic> characteristics = s.characteristics;
                    final readChar = characteristics.firstWhere((c) => c.characteristicUuid == _UART_GUID_TX);
                    final writeChar = characteristics.firstWhere((c) => c.characteristicUuid == _UART_GUID_RX);
                    return ElevatedButton(onPressed: () async {
                      try {
                        String measurementCommand = "<${[electrodeController, startVController, stopVController, scanRateController, cyclesController, ampController, resistorController].map((tc) => tc.text.isEmpty ? "0" : tc.text).join(",")}>";
                        //Define measurement command string
                        final encoded = utf8.encode(measurementCommand); 
                        print(encoded.toString());
                        await writeChar.write(encoded, withoutResponse: writeChar.properties.writeWithoutResponse);
                        final snackBar = snackBarGood("Write: Success");
                        snackBarKeyC.currentState?.removeCurrentSnackBar();
                        snackBarKeyC.currentState?.showSnackBar(snackBar);
                        if (writeChar.properties.read) {
                          await writeChar.read();
                        }
                      } catch (e) {
                        final snackBar = snackBarFail(prettyException("Write Error:", e));
                        snackBarKeyC.currentState?.removeCurrentSnackBar();
                        snackBarKeyC.currentState?.showSnackBar(snackBar);
                      }
                      await readDataFromDevice(readChar);
                    }, child: const Text("Start measurement"));
                  } else {
                    return const Center(child: Text("UART Services are not loaded"));
                  }
                  
                },
              ),
              SfCartesianChart( //For realtime plotting of data
                primaryXAxis: CategoryAxis(),
                series: <LineSeries<MeasData, double>>[
                  LineSeries<MeasData, double> (
                    dataSource: data_array,
                    xValueMapper: (MeasData v, _) => v.voltage,
                    yValueMapper: (MeasData i, _) => i.current
                )
                ]
              )
            ],
          ),
        ),
      ),
    );
  }
  Future<void> stopReadingData(StreamSubscription listener) async {
      csvWrite();  
      await listener.cancel();
  }

  Future<void> readDataFromDevice(BluetoothCharacteristic readChar) async {
    try {
      String op = readChar.isNotifying == false ? "Subscribe" : "Unsubscribe";
      await readChar.setNotifyValue(true);
      final snackBar = snackBarGood("$op : Success");
      snackBarKeyC.currentState?.removeCurrentSnackBar();
      snackBarKeyC.currentState?.showSnackBar(snackBar);
      double? voltage;
      double? current;
      int? index;
      final subscription = readChar.onValueReceived;
      StreamSubscription? listener;
      listener = subscription.listen((val) {
        var result = utf8.decode(val);
        if (result=="end") {
          stopReadingData(listener!);
          return;                          
        }
        else {
        List<String> splitValues = result.split(","); //Split result string to index, voltage, current
        index = int.parse(splitValues[0]);
        voltage = double.parse(splitValues[1]);
        current = double.parse(splitValues[2]);
        var measData = MeasData(index!, voltage!, current!);
        data_array.add(measData); //Append data to data_array
        voltage = null;
        current = null;
        index = null;
        setState(() {
          });
        }
      });
      if (readChar.properties.read) {
        var result = await readChar.read();
      }
    } catch (e) {
      final snackBar = snackBarFail(prettyException("Subscribe Error:", e));
      snackBarKeyC.currentState?.removeCurrentSnackBar();
      snackBarKeyC.currentState?.showSnackBar(snackBar);
    }
  }

  Stream<int> rssiStream({Duration frequency = const Duration(seconds: 5), int? maxItems}) async* {
    var isConnected = true;
    final subscription = widget.device.connectionState.listen((v) {
      isConnected = v == BluetoothConnectionState.connected;
    });
    int i = 0;
    while (isConnected && (maxItems == null || i < maxItems)) {
      try {
        yield await widget.device.readRssi();
      } catch (e) {
        print("Error reading RSSI: $e");
        break;
      }
      await Future.delayed(frequency);
      i++;
    }
    // Device disconnected, stopping RSSI stream
    subscription.cancel();
  }
}

//For the received measurement data to be plotted.
class MeasData {
  final int index;
  final double voltage;
  final double current;
  MeasData(this.index,this.voltage,this.current);
  }

String prettyException(String prefix, dynamic e) {
  if (e is FlutterBluePlusException) {
    return "$prefix ${e.description}";
  } else if (e is PlatformException) {
    return "$prefix ${e.message}";
  }
  return prefix + e.toString();
}