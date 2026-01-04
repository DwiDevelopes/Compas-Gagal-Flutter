import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_compass/flutter_compass.dart';
import 'package:sensors_plus/sensors_plus.dart';
import 'package:geolocator/geolocator.dart';
import 'package:percent_indicator/percent_indicator.dart';
import 'package:vector_math/vector_math.dart' as vector;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:quran/quran.dart' as quran;
import 'package:hijri/digits_converter.dart';
import 'package:hijri/hijri_array.dart';
import 'package:hijri/hijri_calendar.dart';
import 'package:intl/intl.dart';
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Compass Pro - Islamic Edition',
      theme: ThemeData.dark().copyWith(
        primaryColor: Colors.teal,
        colorScheme: ColorScheme.dark(
          primary: Colors.teal,
          secondary: Colors.amber,
          surface: const Color(0xFF121212),
          background: const Color(0xFF0A0A0A),
        ),
        scaffoldBackgroundColor: const Color(0xFF0A0A0A),
        cardColor: const Color(0xFF1E1E1E),
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFF121212),
          elevation: 2,
          centerTitle: true,
        ),
        bottomNavigationBarTheme: const BottomNavigationBarThemeData(
          backgroundColor: Color(0xFF121212),
          selectedItemColor: Colors.teal,
          unselectedItemColor: Colors.grey,
        ),
        useMaterial3: true,
      ),
      home: const MainCompassScreen(),
      debugShowCheckedModeBanner: false,
    );
  }
}

class MainCompassScreen extends StatefulWidget {
  const MainCompassScreen({super.key});

  @override
  State<MainCompassScreen> createState() => _MainCompassScreenState();
}

class _MainCompassScreenState extends State<MainCompassScreen> with TickerProviderStateMixin {
  int _currentIndex = 0;
  double? _heading = 0;
  double? _kiblatDirection = 0;
  double _pitch = 0;
  double _roll = 0;
  double _speed = 0;
  double _lightLevel = 0.5;
  double _emfLevel = 0.3;
  StreamSubscription? _compassSubscription;
  StreamSubscription? _accelerometerSubscription;
  StreamSubscription? _gyroscopeSubscription;
  StreamSubscription? _userAccelerometerSubscription;
  List<double>? _accelerometerValues;
  List<double>? _gyroscopeValues;
  List<double>? _userAccelerometerValues;
  Position? _currentPosition;
  String _selectedCompassType = 'Standard';
  List<String> _compassTypes = ['Standard', 'Kiblat', 'Navigasi', 'Analog', 'Digital'];
  
  // Quran variables
  final ItemScrollController _ayatScrollController = ItemScrollController();
  final ItemPositionsListener _ayatPositionsListener = ItemPositionsListener.create();
  List<String> _surahList = [];
  int _selectedSurah = 1;
  int _totalAyat = 0;
  double _quranFontSize = 28.0;
  bool _showTranslation = true;
  bool _showTajweed = false;
  
  // Tasbih variables
  int _tasbihCount = 0;
  int _tasbihTarget = 33;
  List<String> _tasbihTypes = ['Subhanallah', 'Alhamdulillah', 'Allahu Akbar'];
  int _selectedTasbihType = 0;
  List<Map<String, dynamic>> _tasbihHistory = [];
  
  // Calendar variables
  HijriCalendar _hijriDate = HijriCalendar.now();
  DateTime _gregorianDate = DateTime.now();
  List<PrayerTime> _prayerTimes = [];
  
  // Animation controllers
  late AnimationController _compassAnimationController;
  late AnimationController _needleAnimationController;
  
  // Additional sensors
  double _altitude = 0;
  double _pressure = 1013.25;
  double _humidity = 50.0;
  double _temperature = 25.0;

  @override
  void initState() {
    super.initState();
    _initAnimations();
    _initCompass();
    _initSensors();
    _getLocation();
    _initQuranData();
    _initPrayerTimes();
    _loadTasbihHistory();
    
    // Simulate sensor updates
    _startSensorSimulation();
  }

  void _initAnimations() {
    _compassAnimationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    );
    
    _needleAnimationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    )..repeat(reverse: true);
  }

  void _initCompass() {
    _compassSubscription = FlutterCompass.events?.listen((event) {
      setState(() {
        _heading = event.heading;
        _calculateKiblatDirection();
      });
    });
  }

  void _initSensors() {
    _accelerometerSubscription = accelerometerEvents.listen((event) {
      setState(() {
        _accelerometerValues = [event.x, event.y, event.z];
        _pitch = atan2(event.y, sqrt(event.x * event.x + event.z * event.z));
        _roll = atan2(-event.x, event.z);
      });
    });

    _gyroscopeSubscription = gyroscopeEvents.listen((event) {
      setState(() {
        _gyroscopeValues = [event.x, event.y, event.z];
      });
    });

    _userAccelerometerSubscription = userAccelerometerEvents.listen((event) {
      setState(() {
        _userAccelerometerValues = [event.x, event.y, event.z];
        double acceleration = sqrt(event.x * event.x + event.y * event.y + event.z * event.z);
        _speed = (acceleration * 3.6).clamp(0, 200);
      });
    });
  }

  void _startSensorSimulation() {
    Timer.periodic(const Duration(seconds: 2), (timer) {
      if (mounted) {
        setState(() {
          _lightLevel = (_lightLevel + Random().nextDouble() * 0.2 - 0.1).clamp(0, 1);
          _emfLevel = (_emfLevel + Random().nextDouble() * 0.15 - 0.075).clamp(0, 1);
          _pressure = 1013.25 + Random().nextDouble() * 10 - 5;
          _humidity = 50 + Random().nextDouble() * 20 - 10;
          _temperature = 25 + Random().nextDouble() * 5 - 2.5;
        });
      }
    });
  }

  void _calculateKiblatDirection() async {
    if (_currentPosition != null && _heading != null) {
      const double kaabaLat = 21.4225;
      const double kaabaLng = 39.8262;
      
      double bearing = _calculateBearing(
        _currentPosition!.latitude,
        _currentPosition!.longitude,
        kaabaLat,
        kaabaLng,
      );
      
      setState(() {
        _kiblatDirection = bearing;
      });
    }
  }

  double _calculateBearing(double startLat, double startLng, double endLat, double endLng) {
    startLat = vector.radians(startLat);
    startLng = vector.radians(startLng);
    endLat = vector.radians(endLat);
    endLng = vector.radians(endLng);

    double y = sin(endLng - startLng) * cos(endLat);
    double x = cos(startLat) * sin(endLat) -
        sin(startLat) * cos(endLat) * cos(endLng - startLng);
    
    double bearing = atan2(y, x);
    bearing = vector.degrees(bearing);
    bearing = (bearing + 360) % 360;
    
    return bearing;
  }

  void _getLocation() async {
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) return;

    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) return;
    }

    if (permission == LocationPermission.deniedForever) return;

    Position position = await Geolocator.getCurrentPosition(
      desiredAccuracy: LocationAccuracy.best,
    );
    
    setState(() {
      _currentPosition = position;
      _altitude = position.altitude;
    });
    _calculateKiblatDirection();
  }

  void _initQuranData() {
    _surahList = List.generate(114, (index) => quran.getSurahNameArabic(index + 1));
    _totalAyat = quran.getVerseCount(_selectedSurah);
  }

  void _initPrayerTimes() {
    // In real app, calculate based on location
    _prayerTimes = [
      PrayerTime(name: 'Subuh', time: '04:30', isPassed: false),
      PrayerTime(name: 'Dzuhur', time: '12:15', isPassed: true),
      PrayerTime(name: 'Ashar', time: '15:45', isPassed: false),
      PrayerTime(name: 'Maghrib', time: '18:20', isPassed: false),
      PrayerTime(name: 'Isya', time: '19:45', isPassed: false),
    ];
  }

  void _loadTasbihHistory() async {
    final prefs = await SharedPreferences.getInstance();
    final history = prefs.getStringList('tasbih_history');
    if (history != null) {
      setState(() {
        _tasbihHistory = history.map((e) {
          final parts = e.split('|');
          return {
            'date': parts[0],
            'count': int.parse(parts[1]),
            'type': parts[2],
          };
        }).toList();
      });
    }
  }

  void _saveTasbihCount() async {
    final prefs = await SharedPreferences.getInstance();
    final now = DateFormat('yyyy-MM-dd HH:mm').format(DateTime.now());
    _tasbihHistory.add({
      'date': now,
      'count': _tasbihCount,
      'type': _tasbihTypes[_selectedTasbihType],
    });
    
    final historyList = _tasbihHistory.map((e) => '${e['date']}|${e['count']}|${e['type']}').toList();
    await prefs.setStringList('tasbih_history', historyList);
  }

  @override
  void dispose() {
    _compassSubscription?.cancel();
    _accelerometerSubscription?.cancel();
    _gyroscopeSubscription?.cancel();
    _userAccelerometerSubscription?.cancel();
    _compassAnimationController.dispose();
    _needleAnimationController.dispose();
    super.dispose();
  }

  Widget _buildCompassScreen() {
    final double heading = _heading ?? 0;
    final double? kiblat = _kiblatDirection;

    return Stack(
      children: [
        // Background gradient
        Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                Colors.black.withOpacity(0.8),
                const Color(0xFF0A1F35),
              ],
            ),
          ),
        ),

        // Stars background
        _buildStarsBackground(),

        Column(
          children: [
            // Header with location
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Kompas $_selectedCompassType',
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: Colors.teal,
                        ),
                      ),
                      if (_currentPosition != null)
                        Text(
                          '${_currentPosition!.latitude.toStringAsFixed(4)}°, '
                          '${_currentPosition!.longitude.toStringAsFixed(4)}°',
                          style: const TextStyle(fontSize: 12, color: Colors.grey),
                        ),
                    ],
                  ),
                  _buildCompassTypeSelector(),
                ],
              ),
            ),

            // Main compass
            Expanded(
              child: Center(
                child: Container(
                  width: 320,
                  height: 320,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: Colors.teal.withOpacity(0.3),
                        blurRadius: 20,
                        spreadRadius: 5,
                      ),
                    ],
                  ),
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      // Compass ring
                      Transform.rotate(
                        angle: -heading * (pi / 180),
                        child: Container(
                          width: 300,
                          height: 300,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: Colors.teal.withOpacity(0.5),
                              width: 2,
                            ),
                          ),
                          child: CustomPaint(
                            painter: CompassPainter(),
                          ),
                        ),
                      ),

                      // Direction letters
                      ..._buildDirectionLetters(),

                      // Compass needle
                      AnimatedBuilder(
                        animation: _needleAnimationController,
                        builder: (context, child) {
                          return Transform.rotate(
                            angle: heading * (pi / 180),
                            child: Column(
                              children: [
                                Container(
                                  width: 4,
                                  height: 130,
                                  decoration: BoxDecoration(
                                    gradient: LinearGradient(
                                      colors: [
                                        Colors.red,
                                        Colors.red.withOpacity(0.7),
                                      ],
                                      begin: Alignment.topCenter,
                                      end: Alignment.bottomCenter,
                                    ),
                                    borderRadius: BorderRadius.circular(2),
                                    boxShadow: [
                                      BoxShadow(
                                        color: Colors.red.withOpacity(0.5),
                                        blurRadius: 10,
                                        spreadRadius: 2,
                                      ),
                                    ],
                                  ),
                                ),
                                Container(
                                  width: 4,
                                  height: 130,
                                  decoration: BoxDecoration(
                                    gradient: LinearGradient(
                                      colors: [
                                        Colors.white,
                                        Colors.white.withOpacity(0.7),
                                      ],
                                      begin: Alignment.topCenter,
                                      end: Alignment.bottomCenter,
                                    ),
                                    borderRadius: BorderRadius.circular(2),
                                  ),
                                ),
                              ],
                            ),
                          );
                        },
                      ),

                      // Kiblat indicator
                      if (kiblat != null && _selectedCompassType == 'Kiblat')
                        Transform.rotate(
                          angle: (kiblat - heading) * (pi / 180),
                          child: const Icon(
                            Icons.navigation,
                            color: Colors.green,
                            size: 40,
                          ),
                        ),

                      // Center point
                      Container(
                        width: 20,
                        height: 20,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: Colors.teal,
                          boxShadow: [
                            BoxShadow(
                              color: Colors.teal.withOpacity(0.8),
                              blurRadius: 15,
                              spreadRadius: 5,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),

            // Information panel
            _buildInfoPanel(),
          ],
        ),
      ],
    );
  }

  Widget _buildCompassTypeSelector() {
    return DropdownButtonHideUnderline(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        decoration: BoxDecoration(
          color: const Color(0xFF1E1E1E),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: Colors.teal),
        ),
        child: DropdownButton<String>(
          value: _selectedCompassType,
          dropdownColor: const Color(0xFF1E1E1E),
          style: const TextStyle(color: Colors.white, fontSize: 14),
          items: _compassTypes.map((type) {
            return DropdownMenuItem<String>(
              value: type,
              child: Row(
                children: [
                  Icon(
                    _getCompassIcon(type),
                    size: 16,
                    color: Colors.teal,
                  ),
                  const SizedBox(width: 8),
                  Text(type),
                ],
              ),
            );
          }).toList(),
          onChanged: (value) {
            setState(() {
              _selectedCompassType = value!;
            });
          },
        ),
      ),
    );
  }

  IconData _getCompassIcon(String type) {
    switch (type) {
      case 'Kiblat': return Icons.mosque;
      case 'Navigasi': return Icons.navigation;
      case 'Analog': return Icons.explore;
      case 'Digital': return Icons.design_services;
      default: return Icons.explore;
    }
  }

  List<Widget> _buildDirectionLetters() {
    const directions = ['N', 'NE', 'E', 'SE', 'S', 'SW', 'W', 'NW'];
    return directions.asMap().entries.map((entry) {
      int index = entry.key;
      String direction = entry.value;
      double angle = index * 45 * (pi / 180);
      
      return Transform.rotate(
        angle: angle,
        child: Transform.rotate(
          angle: -angle,
          child: Padding(
            padding: EdgeInsets.only(bottom: 140),
            child: Text(
              direction,
              style: TextStyle(
                color: direction == 'N' ? Colors.red : Colors.white,
                fontSize: direction.length == 1 ? 18 : 12,
                fontWeight: direction == 'N' ? FontWeight.bold : FontWeight.normal,
              ),
            ),
          ),
        ),
      );
    }).toList();
  }

  Widget _buildInfoPanel() {
    return Container(
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF1E1E1E),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.teal.withOpacity(0.3)),
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _buildInfoCard('Heading', '${(_heading ?? 0).toStringAsFixed(1)}°', Icons.explore),
              _buildInfoCard('Kiblat', '${(_kiblatDirection ?? 0).toStringAsFixed(1)}°', Icons.mosque),
              _buildInfoCard('Altitude', '${_altitude.toStringAsFixed(0)} m', Icons.terrain),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _buildInfoCard('Latitude', _currentPosition?.latitude.toStringAsFixed(4) ?? '--', Icons.location_on),
              _buildInfoCard('Longitude', _currentPosition?.longitude.toStringAsFixed(4) ?? '--', Icons.location_on),
              _buildInfoCard('Accuracy', '${_currentPosition?.accuracy?.toStringAsFixed(1) ?? '--'} m', Icons.precision_manufacturing),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildInfoCard(String title, String value, IconData icon) {
    return Column(
      children: [
        Icon(icon, color: Colors.teal, size: 20),
        const SizedBox(height: 4),
        Text(
          title,
          style: const TextStyle(fontSize: 10, color: Colors.grey),
        ),
        Text(
          value,
          style: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.bold,
            color: Colors.white,
          ),
        ),
      ],
    );
  }

  Widget _buildStarsBackground() {
    return IgnorePointer(
      child: Container(
        child: CustomPaint(
          painter: StarsPainter(),
        ),
      ),
    );
  }

  Widget _buildInclinometerScreen() {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Colors.black.withOpacity(0.8),
            const Color(0xFF1A2C42),
          ],
        ),
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Text(
              'Digital Inclinometer',
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: Colors.teal,
                shadows: [
                  Shadow(
                    blurRadius: 10,
                    color: Colors.teal.withOpacity(0.5),
                  ),
                ],
              ),
            ),
          ),
          
          Expanded(
            child: Center(
              child: Container(
                width: 300,
                height: 300,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(20),
                  color: const Color(0xFF1E1E1E).withOpacity(0.7),
                  border: Border.all(color: Colors.teal.withOpacity(0.3)),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.5),
                      blurRadius: 20,
                      spreadRadius: 5,
                    ),
                  ],
                ),
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    // Grid background
                    CustomPaint(
                      painter: InclinometerGridPainter(),
                    ),
                    
                    // Bubble level
                    Transform.translate(
                      offset: Offset(
                        _roll * 80,
                        _pitch * 80,
                      ),
                      child: Container(
                        width: 60,
                        height: 60,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: RadialGradient(
                            colors: [
                              Colors.green.withOpacity(0.8),
                              Colors.green.withOpacity(0.2),
                            ],
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.green.withOpacity(0.5),
                              blurRadius: 15,
                              spreadRadius: 5,
                            ),
                          ],
                        ),
                      ),
                    ),
                    
                    // Center crosshair
                    Container(
                      width: 300,
                      height: 2,
                      color: Colors.red.withOpacity(0.3),
                    ),
                    Container(
                      width: 2,
                      height: 300,
                      color: Colors.red.withOpacity(0.3),
                    ),
                  ],
                ),
              ),
            ),
          ),
          
          _buildSensorDataPanel(),
        ],
      ),
    );
  }

  Widget _buildSensorDataPanel() {
    return Container(
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF1E1E1E),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.teal.withOpacity(0.3)),
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _buildSensorValue('Pitch', '${(_pitch * 180 / pi).toStringAsFixed(1)}°', Colors.green),
              _buildSensorValue('Roll', '${(_roll * 180 / pi).toStringAsFixed(1)}°', Colors.blue),
              _buildSensorValue('Tilt', '${(sqrt(_pitch * _pitch + _roll * _roll) * 180 / pi).toStringAsFixed(1)}°', Colors.amber),
            ],
          ),
          const SizedBox(height: 16),
          if (_accelerometerValues != null)
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Accelerometer Data:',
                  style: TextStyle(color: Colors.grey, fontSize: 12),
                ),
                const SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    _buildAxisData('X', _accelerometerValues![0], Colors.red),
                    _buildAxisData('Y', _accelerometerValues![1], Colors.green),
                    _buildAxisData('Z', _accelerometerValues![2], Colors.blue),
                  ],
                ),
              ],
            ),
        ],
      ),
    );
  }

  Widget _buildSensorValue(String label, String value, Color color) {
    return Column(
      children: [
        Container(
          width: 60,
          height: 60,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: color.withOpacity(0.1),
            border: Border.all(color: color),
          ),
          child: Center(
            child: Text(
              value,
              style: TextStyle(
                color: color,
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          label,
          style: const TextStyle(color: Colors.grey, fontSize: 12),
        ),
      ],
    );
  }

  Widget _buildAxisData(String axis, double value, Color color) {
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: color.withOpacity(0.1),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: color),
          ),
          child: Row(
            children: [
              Text(
                axis,
                style: TextStyle(color: color, fontWeight: FontWeight.bold),
              ),
              const SizedBox(width: 8),
              Text(
                value.toStringAsFixed(2),
                style: const TextStyle(color: Colors.white),
              ),
              const Text(' m/s²', style: TextStyle(fontSize: 10, color: Colors.grey)),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildSpeedometerScreen() {
    final double speedPercent = _speed / 200;
    
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Colors.black.withOpacity(0.8),
            const Color(0xFF2C1A42),
          ],
        ),
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Text(
              'Digital Speedometer',
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: Colors.purple,
                shadows: [
                  Shadow(
                    blurRadius: 10,
                    color: Colors.purple.withOpacity(0.5),
                  ),
                ],
              ),
            ),
          ),
          
          Expanded(
            child: Center(
              child: Container(
                width: 280,
                height: 280,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: Colors.purple.withOpacity(0.3),
                      blurRadius: 20,
                      spreadRadius: 5,
                    ),
                  ],
                ),
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    // Speedometer background
                    CircularPercentIndicator(
                      radius: 130,
                      lineWidth: 20,
                      percent: speedPercent,
                      circularStrokeCap: CircularStrokeCap.round,
                      progressColor: _getSpeedColor(_speed),
                      backgroundColor: Colors.grey.withOpacity(0.1),
                      animation: true,
                      animationDuration: 500,
                    ),
                    
                    // Speed numbers
                    ...List.generate(11, (index) {
                      double angle = (240 + index * 30) * pi / 180;
                      double x = 110 * cos(angle);
                      double y = 110 * sin(angle);
                      
                      return Positioned(
                        left: 140 + x,
                        top: 140 + y,
                        child: Transform.rotate(
                          angle: angle + pi / 2,
                          child: Text(
                            '${index * 20}',
                            style: TextStyle(
                              color: index * 20 <= _speed ? Colors.white : Colors.grey,
                              fontSize: 12,
                            ),
                          ),
                        ),
                      );
                    }),
                    
                    // Speed needle
                    Transform.rotate(
                      angle: (240 + speedPercent * 300) * pi / 180,
                      child: Container(
                        width: 4,
                        height: 110,
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [
                              Colors.red,
                              Colors.orange,
                              Colors.yellow,
                            ],
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                          ),
                          borderRadius: BorderRadius.circular(2),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.red.withOpacity(0.5),
                              blurRadius: 10,
                              spreadRadius: 2,
                            ),
                          ],
                        ),
                      ),
                    ),
                    
                    // Center display
                    Container(
                      width: 160,
                      height: 160,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: const Color(0xFF1E1E1E),
                        border: Border.all(color: Colors.purple.withOpacity(0.5)),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.5),
                            blurRadius: 20,
                            spreadRadius: 5,
                          ),
                        ],
                      ),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            _speed.toStringAsFixed(1),
                            style: const TextStyle(
                              fontSize: 48,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                          ),
                          const Text(
                            'km/h',
                            style: TextStyle(
                              fontSize: 16,
                              color: Colors.grey,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            _getSpeedStatus(_speed),
                            style: TextStyle(
                              fontSize: 12,
                              color: _getSpeedColor(_speed),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          
          _buildAdditionalSensorData(),
        ],
      ),
    );
  }

  Color _getSpeedColor(double speed) {
    if (speed < 40) return Colors.green;
    if (speed < 80) return Colors.yellow;
    if (speed < 120) return Colors.orange;
    return Colors.red;
  }

  String _getSpeedStatus(double speed) {
    if (speed < 20) return 'Diam';
    if (speed < 40) return 'Lambat';
    if (speed < 80) return 'Normal';
    if (speed < 120) return 'Cepat';
    return 'Sangat Cepat';
  }

  Widget _buildAdditionalSensorData() {
    return Container(
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF1E1E1E),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.purple.withOpacity(0.3)),
      ),
      child: Column(
        children: [
          const Text(
            'Environmental Sensors',
            style: TextStyle(
              color: Colors.white,
              fontSize: 16,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _buildEnvSensor('Temperature', '$_temperature°C', Icons.thermostat, Colors.red),
              _buildEnvSensor('Humidity', '$_humidity%', Icons.water_drop, Colors.blue),
              _buildEnvSensor('Pressure', '${_pressure.toStringAsFixed(1)} hPa', Icons.speed, Colors.green),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildEnvSensor(String label, String value, IconData icon, Color color) {
    return Column(
      children: [
        Icon(icon, color: color, size: 24),
        const SizedBox(height: 8),
        Text(
          value,
          style: TextStyle(
            color: color,
            fontSize: 14,
            fontWeight: FontWeight.bold,
          ),
        ),
        Text(
          label,
          style: const TextStyle(color: Colors.grey, fontSize: 10),
        ),
      ],
    );
  }

  Widget _buildLightSensorScreen() {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Colors.black.withOpacity(0.8),
            Color.lerp(Colors.black, Colors.yellow, _lightLevel * 0.3)!,
          ],
        ),
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Text(
              'Light Sensor & Lux Meter',
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: Colors.yellow,
                shadows: [
                  Shadow(
                    blurRadius: 10,
                    color: Colors.yellow.withOpacity(0.5),
                  ),
                ],
              ),
            ),
          ),
          
          Expanded(
            child: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  // Light intensity indicator
                  Container(
                    width: 250,
                    height: 250,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: RadialGradient(
                        colors: [
                          Colors.yellow.withOpacity(_lightLevel),
                          Colors.transparent,
                        ],
                        stops: const [0.1, 1.0],
                      ),
                      border: Border.all(
                        color: Colors.yellow.withOpacity(0.5),
                        width: 2,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.yellow.withOpacity(_lightLevel * 0.5),
                          blurRadius: 50,
                          spreadRadius: 20,
                        ),
                      ],
                    ),
                    child: Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            '${(_lightLevel * 1000).toStringAsFixed(0)}',
                            style: TextStyle(
                              fontSize: 48,
                              fontWeight: FontWeight.bold,
                              color: Colors.yellow,
                              shadows: [
                                Shadow(
                                  blurRadius: 10,
                                  color: Colors.black,
                                ),
                              ],
                            ),
                          ),
                          const Text(
                            'Lux',
                            style: TextStyle(
                              fontSize: 16,
                              color: Colors.yellow,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  
                  const SizedBox(height: 40),
                  
                  // Light level description
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
                    decoration: BoxDecoration(
                      color: Colors.black.withOpacity(0.5),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: Colors.yellow.withOpacity(0.3)),
                    ),
                    child: Column(
                      children: [
                        Text(
                          _getLightDescription(_lightLevel),
                          style: TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.bold,
                            color: Colors.yellow,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          _getLightDetails(_lightLevel),
                          style: const TextStyle(
                            fontSize: 14,
                            color: Colors.grey,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          
          // Light spectrum visualization
          Container(
            margin: const EdgeInsets.all(16),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0xFF1E1E1E),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: Colors.yellow.withOpacity(0.3)),
            ),
            child: Column(
              children: [
                const Text(
                  'Light Spectrum',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 12),
                Container(
                  height: 60,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(10),
                    gradient: LinearGradient(
                      colors: [
                        Colors.black,
                        Colors.purple,
                        Colors.blue,
                        Colors.green,
                        Colors.yellow,
                        Colors.orange,
                        Colors.red,
                      ],
                      stops: const [0, 0.15, 0.3, 0.45, 0.6, 0.75, 1],
                    ),
                  ),
                  child: Center(
                    child: Text(
                      '${_getLightColor(_lightLevel)} Light',
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        shadows: [
                          Shadow(blurRadius: 2, color: Colors.black),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _getLightDescription(double level) {
    if (level < 0.1) return 'Dark Night';
    if (level < 0.25) return 'Moonlight';
    if (level < 0.4) return 'Twilight';
    if (level < 0.6) return 'Overcast Day';
    if (level < 0.8) return 'Daylight';
    return 'Direct Sunlight';
  }

  String _getLightDetails(double level) {
    if (level < 0.1) return '0-100 lux • Suitable for sleeping';
    if (level < 0.25) return '100-400 lux • Suitable for reading with light';
    if (level < 0.4) return '400-1000 lux • Office lighting level';
    if (level < 0.6) return '1000-5000 lux • Overcast daylight';
    if (level < 0.8) return '5000-10000 lux • Full daylight';
    return '10000+ lux • Bright sunlight';
  }

  String _getLightColor(double level) {
    if (level < 0.2) return 'Red-Infrared';
    if (level < 0.4) return 'Yellow';
    if (level < 0.6) return 'White';
    if (level < 0.8) return 'Blue';
    return 'Full Spectrum';
  }

  Widget _buildEMFSensorScreen() {
    final Color emfColor = _getEMFColor(_emfLevel);
    final double emfValue = _emfLevel * 1000;
    
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Colors.black.withOpacity(0.8),
            emfColor.withOpacity(0.1),
          ],
        ),
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Text(
              'EMF Radiation Detector',
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: emfColor,
                shadows: [
                  Shadow(
                    blurRadius: 10,
                    color: emfColor.withOpacity(0.5),
                  ),
                ],
              ),
            ),
          ),
          
          Expanded(
            child: Center(
              child: Container(
                width: 280,
                height: 280,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: emfColor.withOpacity(0.5), width: 2),
                  boxShadow: [
                    BoxShadow(
                      color: emfColor.withOpacity(0.3),
                      blurRadius: 20,
                      spreadRadius: 5,
                    ),
                  ],
                ),
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    // EMF meter dial
                    ...List.generate(11, (index) {
                      double angle = (225 + index * 30) * pi / 180;
                      double x = 120 * cos(angle);
                      double y = 120 * sin(angle);
                      
                      return Positioned(
                        left: 140 + x,
                        top: 140 + y,
                        child: Transform.rotate(
                          angle: angle + pi / 2,
                          child: Text(
                            '${index * 100}',
                            style: TextStyle(
                              color: index * 100 <= emfValue ? emfColor : Colors.grey,
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      );
                    }),
                    
                    // Needle
                    Transform.rotate(
                      angle: (225 + _emfLevel * 300) * pi / 180,
                      child: Container(
                        width: 4,
                        height: 120,
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [
                              emfColor,
                              emfColor.withOpacity(0.7),
                            ],
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                          ),
                          borderRadius: BorderRadius.circular(2),
                          boxShadow: [
                            BoxShadow(
                              color: emfColor.withOpacity(0.5),
                              blurRadius: 10,
                              spreadRadius: 2,
                            ),
                          ],
                        ),
                      ),
                    ),
                    
                    // Center display
                    Container(
                      width: 180,
                      height: 180,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: const Color(0xFF1E1E1E),
                        border: Border.all(color: emfColor.withOpacity(0.5)),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.5),
                            blurRadius: 20,
                            spreadRadius: 5,
                          ),
                        ],
                      ),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            '${emfValue.toStringAsFixed(0)}',
                            style: TextStyle(
                              fontSize: 48,
                              fontWeight: FontWeight.bold,
                              color: emfColor,
                            ),
                          ),
                          const Text(
                            'mG',
                            style: TextStyle(
                              fontSize: 16,
                              color: Colors.grey,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            _getEMFLevelDescription(_emfLevel),
                            style: TextStyle(
                              fontSize: 14,
                              color: emfColor,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          
          _buildEMFInfoPanel(),
        ],
      ),
    );
  }

  Widget _buildEMFInfoPanel() {
    final Color emfColor = _getEMFColor(_emfLevel);
    
    return Container(
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF1E1E1E),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: emfColor.withOpacity(0.3)),
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _buildEMFIndicator('SAFE', Colors.green, _emfLevel < 0.3),
              _buildEMFIndicator('MODERATE', Colors.yellow, _emfLevel >= 0.3 && _emfLevel < 0.6),
              _buildEMFIndicator('HIGH', Colors.orange, _emfLevel >= 0.6 && _emfLevel < 0.8),
              _buildEMFIndicator('DANGER', Colors.red, _emfLevel >= 0.8),
            ],
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: emfColor.withOpacity(0.1),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: emfColor),
            ),
            child: Column(
              children: [
                const Text(
                  'Safety Recommendations:',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  _getEMFSafetyTips(_emfLevel),
                  style: const TextStyle(
                    color: Colors.grey,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEMFIndicator(String label, Color color, bool active) {
    return Column(
      children: [
        Container(
          width: 12,
          height: 12,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: active ? color : color.withOpacity(0.3),
            border: Border.all(color: color),
          ),
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: TextStyle(
            color: active ? color : Colors.grey,
            fontSize: 10,
            fontWeight: active ? FontWeight.bold : FontWeight.normal,
          ),
        ),
      ],
    );
  }

  Color _getEMFColor(double level) {
    if (level < 0.3) return Colors.green;
    if (level < 0.6) return Colors.yellow;
    if (level < 0.8) return Colors.orange;
    return Colors.red;
  }

  String _getEMFLevelDescription(double level) {
    if (level < 0.3) return 'SAFE';
    if (level < 0.6) return 'MODERATE';
    if (level < 0.8) return 'HIGH';
    return 'DANGER';
  }

  String _getEMFSafetyTips(double level) {
    if (level < 0.3) return 'Normal background radiation. No precautions needed.';
    if (level < 0.6) return 'Moderate EMF. Limit prolonged exposure in this area.';
    if (level < 0.8) return 'High EMF detected. Consider moving away from potential sources.';
    return 'Dangerous levels! Immediately move away and identify source.';
  }

  Widget _buildQuranScreen() {
    _totalAyat = quran.getVerseCount(_selectedSurah);
    
    return Column(
      children: [
        // Header with controls
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: const Color(0xFF121212),
            border: Border(bottom: BorderSide(color: Colors.teal.withOpacity(0.3))),
          ),
          child: Column(
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  IconButton(
                    icon: const Icon(Icons.menu, color: Colors.teal),
                    onPressed: _showSurahList,
                  ),
                  const Text(
                    'Al-Quran Digital',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: Colors.teal,
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.settings, color: Colors.teal),
                    onPressed: _showQuranSettings,
                  ),
                ],
              ),
              
              const SizedBox(height: 12),
              
              // Surah selector
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                decoration: BoxDecoration(
                  color: const Color(0xFF1E1E1E),
                  borderRadius: BorderRadius.circular(25),
                  border: Border.all(color: Colors.teal),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.menu_book, color: Colors.teal, size: 20),
                    const SizedBox(width: 8),
                    Expanded(
                      child: DropdownButtonHideUnderline(
                        child: DropdownButton<int>(
                          value: _selectedSurah,
                          dropdownColor: const Color(0xFF1E1E1E),
                          style: const TextStyle(color: Colors.white, fontSize: 16),
                          isExpanded: true,
                          items: List.generate(114, (index) {
                            return DropdownMenuItem<int>(
                              value: index + 1,
                              child: Text(
                                '${index + 1}. ${_surahList[index]}',
                                style: const TextStyle(fontSize: 14),
                              ),
                            );
                          }),
                          onChanged: (value) {
                            setState(() {
                              _selectedSurah = value!;
                              _totalAyat = quran.getVerseCount(_selectedSurah);
                            });
                          },
                        ),
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.teal.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(15),
                      ),
                      child: Text(
                        '$_totalAyat آيات',
                        style: const TextStyle(color: Colors.teal, fontSize: 12),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        
        // Quran content
        Expanded(
          child: ScrollablePositionedList.builder(
            itemCount: _totalAyat,
            itemScrollController: _ayatScrollController,
            itemPositionsListener: _ayatPositionsListener,
            padding: const EdgeInsets.all(16),
            itemBuilder: (context, index) {
              final ayatNumber = index + 1;
              final arabicText = quran.getVerse(_selectedSurah, ayatNumber, verseEndSymbol: true);
              
              return Container(
                margin: const EdgeInsets.only(bottom: 20),
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: const Color(0xFF1E1E1E),
                  borderRadius: BorderRadius.circular(15),
                  border: Border.all(color: Colors.teal.withOpacity(0.2)),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.3),
                      blurRadius: 10,
                      spreadRadius: 2,
                    ),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    // Ayat number
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                          decoration: BoxDecoration(
                            color: Colors.teal.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Text(
                            'Ayat $ayatNumber',
                            style: const TextStyle(color: Colors.teal, fontSize: 12),
                          ),
                        ),
                        Row(
                          children: [
                            IconButton(
                              icon: const Icon(Icons.volume_up, size: 18, color: Colors.teal),
                              onPressed: () => _playAyat(_selectedSurah, ayatNumber),
                            ),
                            IconButton(
                              icon: const Icon(Icons.bookmark_border, size: 18, color: Colors.teal),
                              onPressed: () => _bookmarkAyat(_selectedSurah, ayatNumber),
                            ),
                          ],
                        ),
                      ],
                    ),
                    
                    const SizedBox(height: 16),
                    
                    // Arabic text
                    GestureDetector(
                      onDoubleTap: () => _changeFontSize(),
                      child: Text(
                        arabicText,
                        style: TextStyle(
                          fontSize: _quranFontSize,
                          fontFamily: 'Uthmanic',
                          color: Colors.white,
                          height: 2,
                        ),
                      ),
                    ),
                    
                    if (_showTajweed)
                      Container(
                        margin: const EdgeInsets.only(top: 8),
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: Colors.teal.withOpacity(0.05),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.teal.withOpacity(0.2)),
                        ),
                        child: const Text(
                          'Tajweed rules highlighted',
                          style: TextStyle(color: Colors.teal, fontSize: 12),
                        ),
                      ),
                    
                    if (_showTranslation)
                      Container(
                        margin: const EdgeInsets.only(top: 16),
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.grey[900],
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Terjemahan:',
                              style: TextStyle(
                                color: Colors.teal,
                                fontSize: 14,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'Terjemahan ayat $ayatNumber dari surah ${quran.getSurahName(_selectedSurah)}...',
                              style: const TextStyle(
                                color: Colors.grey,
                                fontSize: 14,
                                height: 1.5,
                              ),
                            ),
                          ],
                        ),
                      ),
                    
                    // Action buttons
                    const SizedBox(height: 16),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceAround,
                      children: [
                        ElevatedButton.icon(
                          icon: const Icon(Icons.arrow_back, size: 16),
                          label: const Text('Sebelumnya'),
                          onPressed: ayatNumber > 1 ? () {
                            _ayatScrollController.scrollTo(
                              index: ayatNumber - 2,
                              duration: const Duration(milliseconds: 300),
                            );
                          } : null,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.teal.withOpacity(0.1),
                            foregroundColor: Colors.teal,
                          ),
                        ),
                        ElevatedButton.icon(
                          icon: const Icon(Icons.copy, size: 16),
                          label: const Text('Salin'),
                          onPressed: () => _copyAyat(arabicText),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.teal.withOpacity(0.1),
                            foregroundColor: Colors.teal,
                          ),
                        ),
                        ElevatedButton.icon(
                          icon: const Icon(Icons.arrow_forward, size: 16),
                          label: const Text('Berikutnya'),
                          onPressed: ayatNumber < _totalAyat ? () {
                            _ayatScrollController.scrollTo(
                              index: ayatNumber,
                              duration: const Duration(milliseconds: 300),
                            );
                          } : null,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.teal.withOpacity(0.1),
                            foregroundColor: Colors.teal,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildTasbihScreen() {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Colors.black.withOpacity(0.8),
            const Color(0xFF1A4235),
          ],
        ),
      ),
      child: Column(
        children: [
          // Header
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Text(
              'Digital Tasbih Counter',
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: Colors.teal,
                shadows: [
                  Shadow(
                    blurRadius: 10,
                    color: Colors.teal.withOpacity(0.5),
                  ),
                ],
              ),
            ),
          ),
          
          Expanded(
            child: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  // Tasbih type selector
                  Container(
                    margin: const EdgeInsets.only(bottom: 30),
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                    decoration: BoxDecoration(
                      color: const Color(0xFF1E1E1E),
                      borderRadius: BorderRadius.circular(25),
                      border: Border.all(color: Colors.teal),
                    ),
                    child: DropdownButtonHideUnderline(
                      child: DropdownButton<int>(
                        value: _selectedTasbihType,
                        dropdownColor: const Color(0xFF1E1E1E),
                        style: const TextStyle(color: Colors.white, fontSize: 18),
                        icon: const Icon(Icons.arrow_drop_down, color: Colors.teal),
                        items: _tasbihTypes.asMap().entries.map((entry) {
                          return DropdownMenuItem<int>(
                            value: entry.key,
                            child: Row(
                              children: [
                                Icon(
                                  _getTasbihIcon(entry.key),
                                  color: Colors.teal,
                                  size: 20,
                                ),
                                const SizedBox(width: 12),
                                Text(entry.value),
                              ],
                            ),
                          );
                        }).toList(),
                        onChanged: (value) {
                          setState(() {
                            _selectedTasbihType = value!;
                          });
                        },
                      ),
                    ),
                  ),
                  
                  // Counter display
                  GestureDetector(
                    onTap: _incrementTasbih,
                    onLongPress: _resetTasbih,
                    child: Container(
                      width: 200,
                      height: 200,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: RadialGradient(
                          colors: [
                            Colors.teal.withOpacity(0.3),
                            Colors.transparent,
                          ],
                        ),
                        border: Border.all(color: Colors.teal, width: 3),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.teal.withOpacity(0.5),
                            blurRadius: 20,
                            spreadRadius: 5,
                          ),
                        ],
                      ),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            _tasbihCount.toString(),
                            style: const TextStyle(
                              fontSize: 72,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                          ),
                          Text(
                            '/$_tasbihTarget',
                            style: const TextStyle(
                              fontSize: 24,
                              color: Colors.grey,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  
                  // Tasbih text
                  Container(
                    margin: const EdgeInsets.only(top: 30),
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: Colors.black.withOpacity(0.5),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: Colors.teal.withOpacity(0.3)),
                    ),
                    child: Column(
                      children: [
                        Text(
                          _tasbihTypes[_selectedTasbihType],
                          style: const TextStyle(
                            fontSize: 28,
                            fontWeight: FontWeight.bold,
                            color: Colors.teal,
                          ),
                        ),
                        const SizedBox(height: 8),
                        const Text(
                          'سُبْحَانَ اللَّهِ',
                          style: TextStyle(
                            fontSize: 24,
                            fontFamily: 'Uthmanic',
                            color: Colors.white,
                          ),
                        ),
                        const SizedBox(height: 8),
                        const Text(
                          'Maha Suci Allah',
                          style: TextStyle(
                            fontSize: 16,
                            color: Colors.grey,
                            fontStyle: FontStyle.italic,
                          ),
                        ),
                      ],
                    ),
                  ),
                  
                  // Action buttons
                  Container(
                    margin: const EdgeInsets.only(top: 30),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        _buildTasbihButton(Icons.refresh, 'Reset', _resetTasbih),
                        const SizedBox(width: 20),
                        _buildTasbihButton(Icons.save, 'Simpan', _saveTasbihCount),
                        const SizedBox(width: 20),
                        _buildTasbihButton(Icons.history, 'Riwayat', _showTasbihHistory),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  IconData _getTasbihIcon(int type) {
    switch (type) {
      case 0: return Icons.star;
      case 1: return Icons.thumb_up;
      case 2: return Icons.whatshot;
      default: return Icons.star;
    }
  }

  Widget _buildTasbihButton(IconData icon, String label, VoidCallback onPressed) {
    return Column(
      children: [
        Container(
          width: 50,
          height: 50,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: Colors.teal.withOpacity(0.1),
            border: Border.all(color: Colors.teal),
          ),
          child: IconButton(
            icon: Icon(icon, color: Colors.teal),
            onPressed: onPressed,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          label,
          style: const TextStyle(color: Colors.grey, fontSize: 12),
        ),
      ],
    );
  }

  void _incrementTasbih() {
    setState(() {
      _tasbihCount++;
      if (_tasbihCount >= _tasbihTarget) {
        _tasbihCount = 0;
        // Play completion sound or show animation
      }
    });
  }

  void _resetTasbih() {
    setState(() {
      _tasbihCount = 0;
    });
  }

  Widget _buildCalendarScreen() {
    final List<String> weekdays = ['Sen', 'Sel', 'Rab', 'Kam', 'Jum', 'Sab', 'Min'];
    final List<String> hijriMonths = [
      'Muharram', 'Safar', 'Rabiul Awal', 'Rabiul Akhir',
      'Jumadil Awal', 'Jumadil Akhir', 'Rajab', 'Sya\'ban',
      'Ramadan', 'Syawal', 'Dzulkaidah', 'Dzulhijjah'
    ];
    
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Colors.black.withOpacity(0.8),
            const Color(0xFF42351A),
          ],
        ),
      ),
      child: Column(
        children: [
          // Header with dates
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0xFF1E1E1E).withOpacity(0.8),
              border: Border(bottom: BorderSide(color: Colors.amber.withOpacity(0.3))),
            ),
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Kalender Islam',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: Colors.amber,
                          ),
                        ),
                        Text(
                          DateFormat('EEEE, d MMMM y').format(_gregorianDate),
                          style: const TextStyle(color: Colors.grey, fontSize: 12),
                        ),
                      ],
                    ),
                    IconButton(
                      icon: const Icon(Icons.today, color: Colors.amber),
                      onPressed: () {
                        setState(() {
                          _gregorianDate = DateTime.now();
                          _hijriDate = HijriCalendar.now();
                        });
                      },
                    ),
                  ],
                ),
                
                const SizedBox(height: 12),
                
                // Hijri date display
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.amber.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(15),
                    border: Border.all(color: Colors.amber),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.calendar_today, color: Colors.amber, size: 16),
                      const SizedBox(width: 8),
                      Text(
                        '${_hijriDate.toFormat("dd MMMM yyyy")} H',
                        style: const TextStyle(
                          color: Colors.amber,
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(width: 16),
                      const Icon(Icons.mosque, color: Colors.amber, size: 16),
                      const SizedBox(width: 8),
                      Text(
                        hijriMonths[_hijriDate.hMonth - 1],
                        style: const TextStyle(color: Colors.amber),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          
          Expanded(
            child: SingleChildScrollView(
              child: Column(
                children: [
                  // Current month calendar
                  Container(
                    margin: const EdgeInsets.all(16),
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: const Color(0xFF1E1E1E),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: Colors.amber.withOpacity(0.3)),
                    ),
                    child: Column(
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            IconButton(
                              icon: const Icon(Icons.arrow_back, color: Colors.amber),
                              onPressed: () => _changeMonth(-1),
                            ),
                            Text(
                              DateFormat('MMMM y').format(_gregorianDate),
                              style: const TextStyle(
                                color: Colors.amber,
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            IconButton(
                              icon: const Icon(Icons.arrow_forward, color: Colors.amber),
                              onPressed: () => _changeMonth(1),
                            ),
                          ],
                        ),
                        
                        const SizedBox(height: 16),
                        
                        // Weekday headers
                        Row(
                          children: weekdays.map((day) {
                            return Expanded(
                              child: Container(
                                padding: const EdgeInsets.symmetric(vertical: 8),
                                child: Text(
                                  day,
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    color: day == 'Jum' ? Colors.amber : Colors.grey,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            );
                          }).toList(),
                        ),
                        
                        // Calendar days
                        ..._buildCalendarDays(),
                      ],
                    ),
                  ),
                  
                  // Prayer times
                  Container(
                    margin: const EdgeInsets.all(16),
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: const Color(0xFF1E1E1E),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: Colors.amber.withOpacity(0.3)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Row(
                          children: [
                            Icon(Icons.access_time, color: Colors.amber),
                            SizedBox(width: 8),
                            Text(
                              'Jadwal Sholat',
                              style: TextStyle(
                                color: Colors.amber,
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                        
                        const SizedBox(height: 12),
                        
                        ..._prayerTimes.map((prayer) {
                          return Container(
                            margin: const EdgeInsets.only(bottom: 8),
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                            decoration: BoxDecoration(
                              color: prayer.isPassed ? Colors.grey[800] : Colors.amber.withOpacity(0.1),
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(
                                color: prayer.isPassed ? Colors.grey : Colors.amber,
                              ),
                            ),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(
                                  prayer.name,
                                  style: TextStyle(
                                    color: prayer.isPassed ? Colors.grey : Colors.amber,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                Text(
                                  prayer.time,
                                  style: TextStyle(
                                    color: prayer.isPassed ? Colors.grey : Colors.amber,
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ],
                            ),
                          );
                        }).toList(),
                      ],
                    ),
                  ),
                  
                  // Islamic events
                  Container(
                    margin: const EdgeInsets.all(16),
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: const Color(0xFF1E1E1E),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: Colors.amber.withOpacity(0.3)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Peristiwa Penting',
                          style: TextStyle(
                            color: Colors.amber,
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        
                        const SizedBox(height: 12),
                        
                        ..._getIslamicEvents().map((event) {
                          return Container(
                            margin: const EdgeInsets.only(bottom: 8),
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: Colors.amber.withOpacity(0.05),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Row(
                              children: [
                                Container(
                                  width: 8,
                                  height: 8,
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    color: Colors.amber,
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Text(
                                    event,
                                    style: const TextStyle(color: Colors.grey),
                                  ),
                                ),
                              ],
                            ),
                          );
                        }).toList(),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  List<Widget> _buildCalendarDays() {
    final firstDay = DateTime(_gregorianDate.year, _gregorianDate.month, 1);
    final lastDay = DateTime(_gregorianDate.year, _gregorianDate.month + 1, 0);
    final daysInMonth = lastDay.day;
    final startingWeekday = firstDay.weekday;
    
    List<Widget> dayWidgets = [];
    List<Widget> weekRow = [];
    
    // Empty cells for days before the first day of month
    for (int i = 1; i < startingWeekday; i++) {
      weekRow.add(const Expanded(child: SizedBox()));
    }
    
    // Calendar days
    for (int day = 1; day <= daysInMonth; day++) {
      final currentDay = DateTime(_gregorianDate.year, _gregorianDate.month, day);
      final isToday = currentDay.day == DateTime.now().day && 
                     currentDay.month == DateTime.now().month && 
                     currentDay.year == DateTime.now().year;
      final isSelected = currentDay.day == _gregorianDate.day;
      
      weekRow.add(
        Expanded(
          child: GestureDetector(
            onTap: () => _selectDay(currentDay),
            child: Container(
              margin: const EdgeInsets.all(2),
              padding: const EdgeInsets.symmetric(vertical: 8),
              decoration: BoxDecoration(
                color: isToday ? Colors.amber.withOpacity(0.2) : 
                       isSelected ? Colors.amber.withOpacity(0.1) : Colors.transparent,
                shape: BoxShape.circle,
                border: isToday ? Border.all(color: Colors.amber) : null,
              ),
              child: Text(
                day.toString(),
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: isToday ? Colors.amber : 
                         isSelected ? Colors.amber : Colors.white,
                  fontWeight: isToday ? FontWeight.bold : FontWeight.normal,
                ),
              ),
            ),
          ),
        ),
      );
      
      if ((startingWeekday - 1 + day) % 7 == 0 || day == daysInMonth) {
        dayWidgets.add(Row(children: weekRow));
        weekRow = [];
      }
    }
    
    return dayWidgets;
  }

  void _changeMonth(int delta) {
    setState(() {
      _gregorianDate = DateTime(_gregorianDate.year, _gregorianDate.month + delta, 1);
    });
  }

  void _selectDay(DateTime day) {
    setState(() {
      _gregorianDate = day;
    });
  }

  List<String> _getIslamicEvents() {
    // This should be replaced with actual Islamic events data
    return [
      '1 Muharram: Tahun Baru Islam',
      '10 Muharram: Hari Asyura',
      '12 Rabiul Awal: Maulid Nabi Muhammad SAW',
      '27 Rajab: Isra\' Mi\'raj',
      '1 Ramadan: Awal Puasa',
      '27 Ramadan: Nuzulul Quran',
      '1 Syawal: Hari Raya Idul Fitri',
      '10 Dzulhijjah: Hari Raya Idul Adha'
    ];
  }

  void _showSurahList() {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1E1E1E),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return Container(
          height: MediaQuery.of(context).size.height * 0.8,
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              const Text(
                'Daftar Surah',
                style: TextStyle(
                  color: Colors.teal,
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 16),
              Expanded(
                child: ListView.builder(
                  itemCount: 114,
                  itemBuilder: (context, index) {
                    final surahNumber = index + 1;
                    return ListTile(
                      leading: Container(
                        width: 30,
                        height: 30,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: Colors.teal.withOpacity(0.1),
                          border: Border.all(color: Colors.teal),
                        ),
                        child: Center(
                          child: Text(
                            surahNumber.toString(),
                            style: const TextStyle(color: Colors.teal, fontSize: 12),
                          ),
                        ),
                      ),
                      title: Text(
                        '${quran.getSurahName(surahNumber)}',
                        style: const TextStyle(color: Colors.white),
                      ),
                      subtitle: Text(
                        '${quran.getVerseCount(surahNumber)} ayat • ${quran.getPlaceOfRevelation(surahNumber)}',
                        style: const TextStyle(color: Colors.grey, fontSize: 12),
                      ),
                      trailing: Text(
                        _surahList[index],
                        style: const TextStyle(fontFamily: 'Uthmanic', fontSize: 18),
                      ),
                      onTap: () {
                        setState(() {
                          _selectedSurah = surahNumber;
                          _totalAyat = quran.getVerseCount(surahNumber);
                        });
                        Navigator.pop(context);
                        _ayatScrollController.scrollTo(
                          index: 0,
                          duration: const Duration(milliseconds: 300),
                        );
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  void _showQuranSettings() {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1E1E1E),
      builder: (context) {
        return Container(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Pengaturan Quran',
                style: TextStyle(
                  color: Colors.teal,
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 20),
              
              // Font size slider
              Row(
                children: [
                  const Icon(Icons.text_fields, color: Colors.teal),
                  const SizedBox(width: 16),
                  const Expanded(
                    child: Text('Ukuran Font', style: TextStyle(color: Colors.white)),
                  ),
                  Text(
                    _quranFontSize.toInt().toString(),
                    style: const TextStyle(color: Colors.teal),
                  ),
                ],
              ),
              Slider(
                value: _quranFontSize,
                min: 20,
                max: 40,
                divisions: 4,
                label: _quranFontSize.toInt().toString(),
                activeColor: Colors.teal,
                inactiveColor: Colors.grey,
                onChanged: (value) {
                  setState(() {
                    _quranFontSize = value;
                  });
                },
              ),
              
              const SizedBox(height: 20),
              
              // Toggles
              SwitchListTile(
                title: const Text('Tampilkan Terjemahan', style: TextStyle(color: Colors.white)),
                value: _showTranslation,
                activeColor: Colors.teal,
                onChanged: (value) {
                  setState(() {
                    _showTranslation = value;
                  });
                },
              ),
              
              SwitchListTile(
                title: const Text('Mode Tajweed', style: TextStyle(color: Colors.white)),
                value: _showTajweed,
                activeColor: Colors.teal,
                onChanged: (value) {
                  setState(() {
                    _showTajweed = value;
                  });
                },
              ),
              
              const SizedBox(height: 20),
              
              ElevatedButton(
                onPressed: () => Navigator.pop(context),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.teal,
                  foregroundColor: Colors.white,
                  minimumSize: const Size(double.infinity, 50),
                ),
                child: const Text('Tutup'),
              ),
            ],
          ),
        );
      },
    );
  }

  void _showTasbihHistory() {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1E1E1E),
      builder: (context) {
        return Container(
          padding: const EdgeInsets.all(20),
          height: MediaQuery.of(context).size.height * 0.7,
          child: Column(
            children: [
              const Text(
                'Riwayat Tasbih',
                style: TextStyle(
                  color: Colors.teal,
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 16),
              Expanded(
                child: _tasbihHistory.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(Icons.history, color: Colors.grey, size: 60),
                            const SizedBox(height: 16),
                            const Text(
                              'Belum ada riwayat tasbih',
                              style: TextStyle(color: Colors.grey),
                            ),
                          ],
                        ),
                      )
                    : ListView.builder(
                        itemCount: _tasbihHistory.length,
                        itemBuilder: (context, index) {
                          final record = _tasbihHistory[_tasbihHistory.length - 1 - index];
                          return Container(
                            margin: const EdgeInsets.only(bottom: 8),
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: Colors.teal.withOpacity(0.1),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Row(
                              children: [
                                Container(
                                  width: 40,
                                  height: 40,
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    color: Colors.teal.withOpacity(0.2),
                                  ),
                                  child: Center(
                                    child: Text(
                                      record['count'].toString(),
                                      style: const TextStyle(
                                        color: Colors.teal,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 16),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        record['type'].toString(),
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                      Text(
                                        record['date'].toString(),
                                        style: const TextStyle(color: Colors.grey, fontSize: 12),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          );
                        },
                      ),
              ),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: () {
                  setState(() {
                    _tasbihHistory.clear();
                  });
                  Navigator.pop(context);
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.red.withOpacity(0.2),
                  foregroundColor: Colors.red,
                ),
                child: const Text('Hapus Semua Riwayat'),
              ),
            ],
          ),
        );
      },
    );
  }

  void _playAyat(int surah, int ayat) {
    // Implement audio playback
    // For now, just show a snackbar
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Memutar Surah $surah Ayat $ayat'),
        backgroundColor: Colors.teal,
      ),
    );
  }

  void _bookmarkAyat(int surah, int ayat) {
    // Implement bookmark functionality
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Ayat $ayat dari Surah ${quran.getSurahName(surah)} ditandai'),
        backgroundColor: Colors.teal,
      ),
    );
  }

  void _copyAyat(String text) {
    // Implement copy to clipboard
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Teks telah disalin ke clipboard'),
        backgroundColor: Colors.teal,
      ),
    );
  }

  void _changeFontSize() {
    setState(() {
      _quranFontSize = _quranFontSize == 28 ? 32 : 28;
    });
  }

  @override
  Widget build(BuildContext context) {
    final List<Widget> _screens = [
      _buildCompassScreen(),
      _buildInclinometerScreen(),
      _buildSpeedometerScreen(),
      _buildLightSensorScreen(),
      _buildEMFSensorScreen(),
      _buildQuranScreen(),
      _buildTasbihScreen(),
      _buildCalendarScreen(),
    ];

    return Scaffold(
      body: _screens[_currentIndex],
      bottomNavigationBar: _buildBottomNavBar(),
    );
  }

  Widget _buildBottomNavBar() {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF121212),
        border: Border(top: BorderSide(color: Colors.teal.withOpacity(0.3))),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.5),
            blurRadius: 10,
            spreadRadius: 5,
          ),
        ],
      ),
      child: BottomNavigationBar(
        currentIndex: _currentIndex,
        onTap: (index) {
          setState(() {
            _currentIndex = index;
          });
        },
        backgroundColor: Colors.transparent,
        selectedItemColor: Colors.teal,
        unselectedItemColor: Colors.grey,
        selectedLabelStyle: const TextStyle(fontSize: 10),
        unselectedLabelStyle: const TextStyle(fontSize: 10),
        type: BottomNavigationBarType.fixed,
        items: const [
          BottomNavigationBarItem(
            icon: Icon(Icons.explore, size: 24),
            label: 'Kompas',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.straighten, size: 24),
            label: 'Level',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.speed, size: 24),
            label: 'Speed',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.lightbulb, size: 24),
            label: 'Cahaya',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.warning, size: 24),
            label: 'EMF',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.menu_book, size: 24),
            label: 'Quran',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.psychology, size: 24),
            label: 'Tasbih',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.calendar_month, size: 24),
            label: 'Kalender',
          ),
        ],
      ),
    );
  }
}

// Custom painters
class CompassPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2;
    final paint = Paint()
      ..color = Colors.teal.withOpacity(0.1)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;

    // Draw concentric circles
    for (int i = 1; i <= 5; i++) {
      canvas.drawCircle(center, radius * i / 5, paint);
    }

    // Draw degree marks
    for (int i = 0; i < 360; i += 5) {
      final angle = i * pi / 180;
      final start = Offset(
        center.dx + (radius - 5) * cos(angle),
        center.dy + (radius - 5) * sin(angle),
      );
      final end = Offset(
        center.dx + radius * cos(angle),
        center.dy + radius * sin(angle),
      );
      
      final markPaint = Paint()
        ..color = i % 90 == 0 ? Colors.red : 
                   i % 30 == 0 ? Colors.yellow : Colors.teal.withOpacity(0.5)
        ..strokeWidth = i % 90 == 0 ? 3 : i % 30 == 0 ? 2 : 1;
      
      canvas.drawLine(start, end, markPaint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class StarsPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final random = Random();
    final paint = Paint()..color = Colors.white.withOpacity(0.3);
    
    for (int i = 0; i < 100; i++) {
      final x = random.nextDouble() * size.width;
      final y = random.nextDouble() * size.height;
      final radius = random.nextDouble() * 1.5;
      
      canvas.drawCircle(Offset(x, y), radius, paint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class InclinometerGridPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final paint = Paint()
      ..color = Colors.teal.withOpacity(0.2)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.5;

    // Draw grid lines
    for (double i = -150; i <= 150; i += 30) {
      // Horizontal lines
      canvas.drawLine(
        Offset(0, center.dy + i),
        Offset(size.width, center.dy + i),
        paint,
      );
      
      // Vertical lines
      canvas.drawLine(
        Offset(center.dx + i, 0),
        Offset(center.dx + i, size.height),
        paint,
      );
    }

    // Draw circle grid
    for (int i = 1; i <= 3; i++) {
      canvas.drawCircle(center, i * 50, paint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

// Data models
class PrayerTime {
  final String name;
  final String time;
  final bool isPassed;

  PrayerTime({
    required this.name,
    required this.time,
    required this.isPassed,
  });
}