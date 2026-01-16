import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:dynamic_color/dynamic_color.dart';
import 'package:appwrite/appwrite.dart' as appwrite;
import 'package:appwrite/models.dart' as models;
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/services.dart';
import 'package:timezone/data/latest.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:url_launcher/url_launcher.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_quill/flutter_quill.dart';

import 'theme.dart';
import 'home.dart';
import 'api_service.dart';

Future<void> _initializeTimezone() async {
  tz_data.initializeTimeZones();
  try {
    final dynamic localTimezone = await FlutterTimezone.getLocalTimezone();
    String timeZoneName = localTimezone.toString();
    print('Raw timezone string: $timeZoneName');

    final RegExp regex = RegExp(r'([A-Za-z]+/[A-Za-z_]+)');
    final match = regex.firstMatch(timeZoneName);

    if (match != null) {
      timeZoneName = match.group(1)!;
    } else {
      if (timeZoneName.startsWith('TimezoneInfo(')) {
        final split = timeZoneName.split(',');
        if (split.isNotEmpty) {
          timeZoneName = split[0].substring('TimezoneInfo('.length);
        }
      }
    }

    tz.setLocalLocation(tz.getLocation(timeZoneName));
    print("Timezone successfully set to: $timeZoneName");
  } catch (e) {
    print("Could not get local timezone: $e");
    try {
      tz.setLocalLocation(tz.getLocation('Asia/Kolkata'));
      print('Fallback to Asia/Kolkata');
    } catch (_) {
      tz.setLocalLocation(tz.getLocation('UTC'));
      print('Fallback to UTC');
    }
  }
}

final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
    FlutterLocalNotificationsPlugin();

Future<void> _initializeNotifications() async {
  const AndroidInitializationSettings initializationSettingsAndroid =
      AndroidInitializationSettings('@mipmap/launcher_icon');

  const DarwinInitializationSettings initializationSettingsDarwin =
      DarwinInitializationSettings(
        requestAlertPermission: false,
        requestBadgePermission: false,
        requestSoundPermission: false,
      );

  const InitializationSettings initializationSettings = InitializationSettings(
    android: initializationSettingsAndroid,
    iOS: initializationSettingsDarwin,
  );

  await flutterLocalNotificationsPlugin.initialize(initializationSettings);
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);

  await _initializeTimezone();
  await _initializeNotifications();

  await AppConfig.loadFromPrefs();

  appwrite.Client client = appwrite.Client();
  client
      .setEndpoint(AppConfig.appwriteEndpoint)
      .setProject(AppConfig.appwriteProjectId)
      .setSelfSigned(status: true);
  appwrite.Account account = appwrite.Account(client);
  runApp(MyApp(account: account));
}

class MyApp extends StatefulWidget {
  final appwrite.Account account;
  const MyApp({super.key, required this.account});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> with WidgetsBindingObserver {
  bool _dynamicColor = true;
  String _themeMode = 'auto';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadThemeSettings();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _loadThemeSettings();
    }
  }

  Future<void> _loadThemeSettings() async {
    final prefs = await SharedPreferences.getInstance();
    if (mounted) {
      setState(() {
        _dynamicColor = prefs.getBool('dynamic_color') ?? true;
        _themeMode = prefs.getString('theme_mode') ?? 'auto';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return DynamicColorBuilder(
      builder: (ColorScheme? lightDynamic, ColorScheme? darkDynamic) {
        ColorScheme lightColorScheme;
        ColorScheme darkColorScheme;

        if (_dynamicColor && lightDynamic != null && darkDynamic != null) {
          lightColorScheme = lightDynamic;
          darkColorScheme = darkDynamic;
        } else {
          lightColorScheme = MaterialTheme(
            GoogleFonts.gabaritoTextTheme(),
          ).light().colorScheme;
          darkColorScheme = MaterialTheme(
            GoogleFonts.gabaritoTextTheme(),
          ).dark().colorScheme;
        }

        ThemeMode mode = ThemeMode.system;
        if (!_dynamicColor) {
          if (_themeMode == 'light') mode = ThemeMode.light;
          if (_themeMode == 'dark') mode = ThemeMode.dark;
        }

        return MaterialApp(
          theme: ThemeData(
            colorScheme: lightColorScheme,
            textTheme: GoogleFonts.gabaritoTextTheme(),
            useMaterial3: true,
          ),
          darkTheme: ThemeData(
            colorScheme: darkColorScheme,
            textTheme: GoogleFonts.gabaritoTextTheme(),
            useMaterial3: true,
          ),
          themeMode: mode,
          localizationsDelegates: const [
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
            FlutterQuillLocalizations.delegate,
          ],
          supportedLocales: const [Locale('en', 'US')],
          builder: (context, child) {
            final brightness = MediaQuery.of(context).platformBrightness;
            final isDarkMode = mode == ThemeMode.system
                ? brightness == Brightness.dark
                : mode == ThemeMode.dark;
            return AnnotatedRegion<SystemUiOverlayStyle>(
              value: SystemUiOverlayStyle(
                systemNavigationBarColor: Colors.transparent,
                systemNavigationBarIconBrightness: isDarkMode
                    ? Brightness.light
                    : Brightness.dark,
                statusBarColor: Colors.transparent,
                statusBarIconBrightness: isDarkMode
                    ? Brightness.light
                    : Brightness.dark,
              ),
              child: child!,
            );
          },
          home: AuthCheck(account: widget.account),
          debugShowCheckedModeBanner: false,
        );
      },
    );
  }
}

class AuthCheck extends StatefulWidget {
  final appwrite.Account account;
  const AuthCheck({super.key, required this.account});

  @override
  _AuthCheckState createState() => _AuthCheckState();
}

class _AuthCheckState extends State<AuthCheck> {
  bool isLoading = true;
  models.User? loggedInUser;
  final _storage = const FlutterSecureStorage();

  @override
  void initState() {
    super.initState();
    _checkLoginStatusAndFetchToken();
  }

  Future<void> _checkLoginStatusAndFetchToken() async {
    try {
      final user = await widget.account.get();
      try {
        final jwt = await widget.account.createJWT();
        await _storage.write(key: 'jwt_token', value: jwt.jwt);
      } catch (e) {
        print("Failed to create JWT: $e");
        await _storage.delete(key: 'jwt_token');
      }
      setState(() {
        loggedInUser = user;
        isLoading = false;
      });
    } catch (e) {
      await _storage.delete(key: 'jwt_token');
      AppConfig.resetToDefault();
      setState(() {
        isLoading = false;
        loggedInUser = null;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (isLoading) {
      return Scaffold(
        backgroundColor: Theme.of(context).colorScheme.surface,
        body: Center(child: CircularProgressIndicator()),
      );
    }
    if (loggedInUser != null) {
      return HomePage(account: widget.account);
    }
    return AuraOnboarding(account: widget.account);
  }
}

class AuraOnboarding extends StatefulWidget {
  final appwrite.Account account;
  const AuraOnboarding({super.key, required this.account});

  @override
  State<AuraOnboarding> createState() => _AuraOnboardingState();
}

class DynamicColorSvg extends StatelessWidget {
  const DynamicColorSvg({
    super.key,
    required this.assetName,
    required this.color,
    this.width,
    this.height,
    this.fit = BoxFit.contain,
  });

  final String assetName;
  final Color color;
  final double? width;
  final double? height;
  final BoxFit fit;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<String>(
      future: DefaultAssetBundle.of(context).loadString(assetName),
      builder: (BuildContext context, AsyncSnapshot<String> snapshot) {
        String svgStringToShow;

        if (snapshot.connectionState == ConnectionState.waiting &&
            !snapshot.hasData) {
          return SizedBox(width: width, height: height);
        }

        if (snapshot.hasError) {
          print('Error loading SVG $assetName: ${snapshot.error}');
          svgStringToShow =
              '<svg version="1.1" xmlns="http://www.w3.org/2000/svg" viewBox="0 0 1 1"></svg>';
        } else {
          svgStringToShow =
              snapshot.data ??
              '<svg version="1.1" xmlns="http://www.w3.org/2000/svg" viewBox="0 0 1 1"></svg>';
        }

        final String r = color.red.toRadixString(16).padLeft(2, '0');
        final String g = color.green.toRadixString(16).padLeft(2, '0');
        final String b = color.blue.toRadixString(16).padLeft(2, '0');
        final String colorHex = '#$r$g$b'.toUpperCase();

        final RegExp currentColorRegExp = RegExp(
          r'currentColor',
          caseSensitive: false,
        );
        String finalSvgString = svgStringToShow.replaceAll(
          currentColorRegExp,
          colorHex,
        );

        return SvgPicture.string(
          finalSvgString,
          width: width,
          height: height,
          fit: fit,
        );
      },
    );
  }
}

class _AuraOnboardingState extends State<AuraOnboarding> {
  final PageController _featureController = PageController();
  int _featurePage = 0;

  final TextEditingController emailController = TextEditingController();
  final TextEditingController passwordController = TextEditingController();
  final TextEditingController nameController = TextEditingController();

  bool showSignup = false;
  bool showLogin = false;
  bool isBusy = false;
  String error = '';
  bool stopCarousel = false;
  final _storage = const FlutterSecureStorage();
  bool _isPasswordVisible = false;
  int _tapCount = 0;

  late final ApiService _apiService = ApiService(account: widget.account);

  @override
  void initState() {
    super.initState();
    Future.microtask(_autoPlayFeatures);
  }

  void _autoPlayFeatures() async {
    const int featureCount = 6;
    while (mounted && !stopCarousel) {
      await Future.delayed(const Duration(seconds: 5));
      if (!mounted || stopCarousel) break;
      int next = (_featurePage + 1) % featureCount;
      if (_featureController.hasClients) {
        _featureController.animateToPage(
          next,
          duration: const Duration(milliseconds: 400),
          curve: Curves.easeInOut,
        );
      }
    }
  }

  Future<void> _launchUrl(String url) async {
    if (!await launchUrl(Uri.parse(url))) {
      showError('Could not launch URL');
    }
  }

  void _showApiEndpointDialog() {
    final controller = TextEditingController(text: AppConfig.baseUrl);
    String? errorText;
    bool isLoading = false;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        bool showAppwriteSettings = false;
        final projectIdController = TextEditingController(
          text: AppConfig.appwriteProjectId,
        );
        final endpointController = TextEditingController(
          text: AppConfig.appwriteEndpoint,
        );

        return StatefulBuilder(
          builder: (context, setState) {
            final theme = Theme.of(context);

            Future<void> checkAndSaveEndpoint() async {
              setState(() {
                isLoading = true;
                errorText = null;
              });

              final url = controller.text.trim();
              final awEndpoint = endpointController.text.trim();
              final awProject = projectIdController.text.trim();

              if (url.isEmpty ||
                  !(url.startsWith('http://') || url.startsWith('https://'))) {
                setState(() {
                  errorText = 'Please enter a valid URL (http/https).';
                  isLoading = false;
                });
                return;
              }

              try {
                final response = await http
                    .get(Uri.parse(url))
                    .timeout(const Duration(seconds: 5));

                if (response.statusCode == 200) {
                  try {
                    final Map<String, dynamic> data = jsonDecode(response.body);
                    final String? autoEndpoint = data['appwriteEndpoint'];
                    final String? autoProject = data['appwriteProjectId'];

                    if (autoEndpoint != null && autoProject != null) {
                      AppConfig.setBaseUrl(url);
                      AppConfig.setAppwriteConfig(autoEndpoint, autoProject);
                      await AppConfig.saveToPrefs();

                      widget.account.client
                          .setEndpoint(autoEndpoint)
                          .setProject(autoProject);

                      if (mounted) {
                        Navigator.of(context).pop();
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text(
                              'Connected and configured successfully!',
                            ),
                            behavior: SnackBarBehavior.floating,
                          ),
                        );
                      }
                      return;
                    }
                  } catch (_) {}

                  if (response.body == 'feel alive.') {
                    AppConfig.setBaseUrl(url);
                    AppConfig.setAppwriteConfig(awEndpoint, awProject);
                    await AppConfig.saveToPrefs();

                    widget.account.client
                        .setEndpoint(awEndpoint)
                        .setProject(awProject);

                    if (mounted) {
                      Navigator.of(context).pop();
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Settings updated successfully.'),
                          behavior: SnackBarBehavior.floating,
                        ),
                      );
                    }
                  } else {
                    setState(() {
                      errorText = 'Invalid server response.';
                      isLoading = false;
                    });
                  }
                } else {
                  setState(() {
                    errorText = 'Server error: ${response.statusCode}';
                    isLoading = false;
                  });
                }
              } catch (e) {
                setState(() {
                  errorText = 'Failed to connect to the endpoint.';
                  isLoading = false;
                });
              }
            }

            return AlertDialog(
              title: Text(
                'Server API Endpoint',
                style: TextStyle(color: theme.colorScheme.onSurface),
              ),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    TextField(
                      controller: controller,
                      decoration: InputDecoration(
                        hintText: 'http://localhost:3000',
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        errorText: errorText,
                      ),
                      style: TextStyle(color: theme.colorScheme.onSurface),
                      enabled: !isLoading,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'Appwrite configuration will be fetched from server automatically.',
                      style: TextStyle(
                        fontSize: 12,
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: isLoading
                      ? null
                      : () => Navigator.of(context).pop(),
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  onPressed: isLoading ? null : checkAndSaveEndpoint,
                  child: isLoading
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Save'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  void showError(String msg) {
    if (!mounted) return;
    setState(() => error = msg);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: Colors.red.shade400),
    );
  }

  Future<void> _handleSuccessfulAuth() async {
    if (!mounted) return;

    if (mounted) {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (context) => HomePage(account: widget.account),
        ),
      );
    }
  }

  Future<void> register() async {
    if (!mounted) return;
    setState(() => isBusy = true);
    try {
      await widget.account.create(
        userId: appwrite.ID.unique(),
        email: emailController.text.trim(),
        password: passwordController.text,
        name: nameController.text.trim(),
      );
      await widget.account.createEmailPasswordSession(
        email: emailController.text.trim(),
        password: passwordController.text,
      );
      final jwt = await widget.account.createJWT();
      await _storage.write(key: 'jwt_token', value: jwt.jwt);
      TextInput.finishAutofillContext();
      await _handleSuccessfulAuth();
    } catch (e) {
      showError(
        'Registration failed: ${e.toString().replaceAll('AppwriteException: ', '')}',
      );
    }
    if (mounted) {
      setState(() => isBusy = false);
    }
  }

  Future<void> login() async {
    if (!mounted) return;
    setState(() => isBusy = true);
    try {
      await widget.account.createEmailPasswordSession(
        email: emailController.text.trim(),
        password: passwordController.text,
      );
      final jwt = await widget.account.createJWT();
      await _storage.write(key: 'jwt_token', value: jwt.jwt);
      await _handleSuccessfulAuth();
    } catch (e) {
      showError(
        'Login failed: ${e.toString().replaceAll('AppwriteException: ', '')}',
      );
    }
    if (mounted) {
      setState(() => isBusy = false);
    }
  }

  void _showVerificationSentDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return AlertDialog(
          title: const Text('Verify Your Email'),
          content: const Text(
            "We've sent you a verification email. Please click on the link in your inbox and reopen the app to continue.",
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
                setState(() {
                  showSignup = false;
                  showLogin = false;
                  stopCarousel = false;
                  Future.microtask(_autoPlayFeatures);
                });
              },
              child: const Text('OK'),
            ),
          ],
        );
      },
    );
  }

  void _showForgotPasswordDialog() {
    final TextEditingController forgotEmailController = TextEditingController();
    String? errorText;
    bool isSending = false;

    showDialog(
      context: context,
      barrierDismissible: !isSending,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setStateDialog) {
            final theme = Theme.of(context);

            Future<void> sendResetLink() async {
              final email = forgotEmailController.text.trim();
              if (email.isEmpty) {
                setStateDialog(() {
                  errorText = 'Please enter your email.';
                });
                return;
              }

              setStateDialog(() {
                isSending = true;
                errorText = null;
              });

              try {
                await widget.account.createRecovery(
                  email: email,
                  url: 'https://aurachieve.authui.site/forgot-password-finish',
                );
                if (mounted) {
                  Navigator.of(context).pop();
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Password reset link sent to your email.'),
                      behavior: SnackBarBehavior.floating,
                    ),
                  );
                }
              } catch (e) {
                setStateDialog(() {
                  errorText = 'Failed to send link. Wrong email, probably.';
                  isSending = false;
                });
              }
            }

            return AlertDialog(
              title: Text(
                'Forgot Password',
                style: TextStyle(color: theme.colorScheme.onSurface),
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    "We'll send you a password reset email.",
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: forgotEmailController,
                    keyboardType: TextInputType.emailAddress,
                    autofocus: true,
                    style: TextStyle(color: theme.colorScheme.onSurface),
                    decoration: InputDecoration(
                      labelText: 'Email',
                      errorText: errorText,
                    ),
                    enabled: !isSending,
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: isSending
                      ? null
                      : () => Navigator.of(context).pop(),
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  onPressed: isSending ? null : sendResetLink,
                  child: isSending
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Send'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Widget _authHeader({required bool isSignup}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 16.0, horizontal: 24.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            isSignup ? 'Welcome aboard!' : 'Welcome Back!',
            style: GoogleFonts.ebGaramond(
              fontSize: 32,
              fontWeight: FontWeight.bold,
              color: Theme.of(context).colorScheme.primary,
            ),
            textAlign: TextAlign.start,
          ),
          SizedBox(height: 8),
          Text(
            isSignup
                ? 'We\'re glad to have you here. Can\'t wait to see a better version of you!'
                : 'Glad to see you again!',
            style: GoogleFonts.gabarito(
              fontSize: 18,
              color: Theme.of(context).colorScheme.secondary,
            ),
            textAlign: TextAlign.start,
          ),
        ],
      ),
    );
  }

  Widget _featuresCarousel() {
    final features = [
      {
        'svg': 'assets/img/welcome.svg',
        'title': 'Welcome to AurAchieve',
        'desc': 'Prepare to live a better life.',
      },
      {
        'svg': 'assets/img/feature1.svg',
        'title': 'Aura',
        'desc': 'Earn and track your Aura as you complete tasks.',
      },
      {
        'svg': 'assets/img/feature2.svg',
        'title': 'AI Powered',
        'desc':
            'With AI helping you with every step of the way, you\'ll never feel lost.',
      },
      {
        'svg': 'assets/img/habit.svg',
        'title': 'Habits',
        'desc': 'Build good habits and break bad ones.',
      },
      {
        'svg': 'assets/img/social.svg',
        'title': 'Social Media Blocker',
        'desc': 'Block your social media apps and touch some grass.',
      },
      {
        'svg': 'assets/img/study.svg',
        'title': 'Study Planner',
        'desc': 'Plan your study sessions with AI and stay on track.',
      },
    ];

    return Expanded(
      child: Stack(
        children: [
          PageView.builder(
            controller: _featureController,
            itemCount: features.length,
            onPageChanged: (i) => setState(() => _featurePage = i),
            itemBuilder: (context, i) => Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 32.0,
                      vertical: 16.0,
                    ),
                    child: DynamicColorSvg(
                      assetName: features[i]['svg']!,
                      color: Theme.of(context).colorScheme.primary,
                      fit: BoxFit.contain,
                    ),
                  ),
                ),
                SizedBox(height: 24),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24.0),
                  child: Column(
                    children: [
                      Text(
                        features[i]['title']!,
                        style: GoogleFonts.ebGaramond(
                          fontSize: 32,
                          fontWeight: FontWeight.bold,
                          color: Theme.of(context).colorScheme.primary,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      SizedBox(height: 12),
                      Text(
                        features[i]['desc']!,
                        style: GoogleFonts.gabarito(
                          fontSize: 20,
                          color: Theme.of(context).colorScheme.secondary,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                ),
                SizedBox(height: 48),
              ],
            ),
          ),
          Positioned(
            bottom: 24,
            left: 0,
            right: 0,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(features.length, (idx) {
                return AnimatedContainer(
                  duration: Duration(milliseconds: 300),
                  margin: EdgeInsets.symmetric(horizontal: 4),
                  width: _featurePage == idx ? 18 : 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: _featurePage == idx
                        ? Theme.of(context).colorScheme.primary
                        : Theme.of(
                            context,
                          ).colorScheme.primary.withOpacity(0.3),
                    borderRadius: BorderRadius.circular(4),
                  ),
                );
              }),
            ),
          ),
        ],
      ),
    );
  }

  Widget _signupForm() {
    return AutofillGroup(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24.0),
        child: Column(
          children: [
            TextField(
              controller: nameController,
              style: TextStyle(color: Theme.of(context).colorScheme.onSurface),
              decoration: InputDecoration(
                labelText: 'Name',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                prefixIcon: Icon(Icons.person_rounded),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 18,
                ),
              ),
              autofillHints: [AutofillHints.name],
              textInputAction: TextInputAction.next,
            ),
            SizedBox(height: 16),
            TextField(
              controller: emailController,
              style: TextStyle(color: Theme.of(context).colorScheme.onSurface),
              decoration: InputDecoration(
                labelText: 'Email',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                prefixIcon: Icon(Icons.email_rounded),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 18,
                ),
              ),
              keyboardType: TextInputType.emailAddress,
              autofillHints: [AutofillHints.username, AutofillHints.email],
              textInputAction: TextInputAction.next,
            ),
            SizedBox(height: 16),
            TextField(
              controller: passwordController,
              style: TextStyle(color: Theme.of(context).colorScheme.onSurface),
              decoration: InputDecoration(
                labelText: 'Password',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                prefixIcon: Icon(Icons.lock_rounded),
                suffixIcon: IconButton(
                  icon: Icon(
                    _isPasswordVisible
                        ? Icons.visibility_rounded
                        : Icons.visibility_off_rounded,
                  ),
                  onPressed: () {
                    setState(() {
                      _isPasswordVisible = !_isPasswordVisible;
                    });
                  },
                ),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 18,
                ),
              ),
              obscureText: !_isPasswordVisible,
              autofillHints: [AutofillHints.newPassword],
              textInputAction: TextInputAction.done,
            ),
          ],
        ),
      ),
    );
  }

  Widget _loginForm() {
    return AutofillGroup(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            TextField(
              controller: emailController,
              style: TextStyle(color: Theme.of(context).colorScheme.onSurface),
              decoration: InputDecoration(
                labelText: 'Email',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                prefixIcon: Icon(Icons.email_rounded),
              ),
              keyboardType: TextInputType.emailAddress,
              autofillHints: [AutofillHints.username, AutofillHints.email],
            ),
            SizedBox(height: 16),
            TextField(
              controller: passwordController,
              style: TextStyle(color: Theme.of(context).colorScheme.onSurface),
              decoration: InputDecoration(
                labelText: 'Password',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                prefixIcon: Icon(Icons.lock_rounded),
                suffixIcon: IconButton(
                  icon: Icon(
                    _isPasswordVisible
                        ? Icons.visibility_rounded
                        : Icons.visibility_off_rounded,
                  ),
                  onPressed: () {
                    setState(() {
                      _isPasswordVisible = !_isPasswordVisible;
                    });
                  },
                ),
              ),
              obscureText: !_isPasswordVisible,
              autofillHints: [AutofillHints.password],
            ),
            TextButton(
              onPressed: _showForgotPasswordDialog,
              child: Text(
                'Forgot Password?',
                style: GoogleFonts.gabarito(
                  color: Theme.of(context).colorScheme.secondary,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLegalText() {
    final theme = Theme.of(context);
    final linkStyle = TextStyle(
      color: theme.colorScheme.primary,
      decoration: TextDecoration.underline,
    );

    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 8, 24, 0),
      child: RichText(
        textAlign: TextAlign.center,
        text: TextSpan(
          style: TextStyle(
            fontSize: 12,
            color: theme.colorScheme.onSurface.withOpacity(0.6),
            fontFamily: GoogleFonts.gabarito().fontFamily,
          ),
          children: [
            const TextSpan(text: 'By continuing, you agree to our '),
            TextSpan(
              text: 'Terms & Conditions',
              style: linkStyle,
              recognizer: TapGestureRecognizer()
                ..onTap = () {
                  _launchUrl('https://google.com');
                },
            ),
            const TextSpan(text: ' and '),
            TextSpan(
              text: 'Privacy Policy',
              style: linkStyle,
              recognizer: TapGestureRecognizer()
                ..onTap = () {
                  _launchUrl('https://aurachieve.com/privacy');
                },
            ),
            const TextSpan(text: '.'),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.surface,
      resizeToAvoidBottomInset: true,
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final showForm = showSignup || showLogin;
            final formWidget = showSignup
                ? _signupForm()
                : showLogin
                ? _loginForm()
                : null;

            Widget currentScreen;
            if (!showForm) {
              currentScreen = GestureDetector(
                onTap: () {
                  setState(() => _tapCount++);
                  if (_tapCount >= 7) {
                    _tapCount = 0;
                    _showApiEndpointDialog();
                  }
                },
                behavior: HitTestBehavior.opaque,
                child: Column(
                  key: const ValueKey('carousel'),
                  children: [
                    Expanded(child: _featuresCarousel()),
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 24,
                        vertical: 16,
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          FilledButton.icon(
                            icon: Icon(Icons.rocket_launch_rounded),
                            onPressed: () => setState(() {
                              showSignup = true;
                              stopCarousel = true;
                            }),
                            label: Text(
                              'Get Started',
                              style: GoogleFonts.gabarito(fontSize: 18),
                            ),
                            style: FilledButton.styleFrom(
                              minimumSize: Size(double.infinity, 48),
                            ),
                          ),
                          SizedBox(height: 16),
                          OutlinedButton.icon(
                            icon: Icon(Icons.login_rounded),
                            onPressed: () => setState(() {
                              showLogin = true;
                              stopCarousel = true;
                            }),
                            label: Text(
                              'Login',
                              style: GoogleFonts.gabarito(fontSize: 18),
                            ),
                            style: OutlinedButton.styleFrom(
                              minimumSize: Size(double.infinity, 48),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              );
            } else {
              currentScreen = Column(
                children: [
                  Expanded(
                    child: SingleChildScrollView(
                      key: const ValueKey('form'),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          SizedBox(height: 24),
                          _authHeader(isSignup: showSignup),
                          SizedBox(height: 24),
                          formWidget ?? SizedBox.shrink(),
                        ],
                      ),
                    ),
                  ),
                  Padding(
                    padding: EdgeInsets.only(
                      left: 24,
                      right: 24,
                      bottom: MediaQuery.of(context).padding.bottom > 0
                          ? MediaQuery.of(context).padding.bottom
                          : 16,
                      top: 8,
                    ),
                    child: Column(
                      children: [
                        _buildLegalText(),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            TextButton(
                              onPressed: () {
                                setState(() {
                                  showLogin = false;
                                  showSignup = false;
                                  stopCarousel = false;
                                  Future.microtask(_autoPlayFeatures);
                                });
                              },
                              child: Text(
                                'Back',
                                style: GoogleFonts.gabarito(),
                              ),
                            ),
                            FilledButton.icon(
                              icon: Icon(
                                showSignup
                                    ? Icons.person_add_alt_1_rounded
                                    : Icons.login_rounded,
                              ),
                              onPressed: isBusy
                                  ? null
                                  : (showSignup ? register : login),
                              label: isBusy
                                  ? SizedBox(
                                      height: 20,
                                      width: 20,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                      ),
                                    )
                                  : Text(
                                      showSignup ? 'Sign Up' : 'Login',
                                      style: GoogleFonts.gabarito(fontSize: 18),
                                    ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              );
            }

            return AnimatedSwitcher(
              duration: const Duration(milliseconds: 500),
              transitionBuilder: (Widget child, Animation<double> animation) {
                return FadeTransition(opacity: animation, child: child);
              },
              child: currentScreen,
            );
          },
        ),
      ),
    );
  }
}
