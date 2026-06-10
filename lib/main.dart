import 'dart:async';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:app_links/app_links.dart';
import 'screens/view_memory.dart';
import 'screens/email_verification.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:dynamic_color/dynamic_color.dart';
import 'package:appwrite/appwrite.dart' as appwrite;
import 'package:appwrite/models.dart' as models;
import 'package:appwrite/enums.dart' as enums;
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

final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();
bool isVerificationDialogOpen = false;

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
  late final ApiService _apiService;
  late final AppLinks _appLinks;
  StreamSubscription<Uri>? _linkSubscription;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _apiService = ApiService(account: widget.account);
    _loadThemeSettings();
    _initDeepLinks();
  }

  @override
  void dispose() {
    _linkSubscription?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  void _initDeepLinks() {
    _appLinks = AppLinks();

    // Check initial link (when app is opened via link from a cold state)
    _appLinks.getInitialLink().then((uri) {
      if (uri != null) {
        _handleDeepLink(uri);
      }
    });

    // Listen to incoming links (when app is already running)
    _linkSubscription = _appLinks.uriLinkStream.listen(
      (uri) {
        _handleDeepLink(uri);
      },
      onError: (err) {
        debugPrint('Deep Link Error: $err');
      },
    );
  }

  void _handleDeepLink(Uri uri) {
    final segments = uri.pathSegments;
    if (segments.length >= 3 && segments[1] == 'memory') {
      final memoryId = segments[2];
      _navigateToPublicMemory(memoryId);
    }
  }

  Future<void> _navigateToPublicMemory(String memoryId) async {
    while (navigatorKey.currentState == null) {
      await Future.delayed(const Duration(milliseconds: 100));
    }
    final context = navigatorKey.currentContext;
    if (context == null) return;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => const Center(child: CircularProgressIndicator()),
    );

    try {
      final memory = await _apiService.getPublicMemory(memoryId);

      // Dismiss loading dialog
      if (navigatorKey.currentContext != null) {
        Navigator.of(navigatorKey.currentContext!).pop();
      }

      navigatorKey.currentState!.push(
        MaterialPageRoute(
          builder: (context) => MemoryDetailPage(
            memory: memory,
            apiService: _apiService,
            e2eEnabled: false,
          ),
        ),
      );
    } catch (e) {
      // Dismiss loading dialog
      if (navigatorKey.currentContext != null) {
        Navigator.of(navigatorKey.currentContext!).pop();
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to load memory: $e'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
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

        final baseTextTheme = GoogleFonts.gabaritoTextTheme();
        final lightTheme = MaterialTheme(baseTextTheme).theme(lightColorScheme);
        final darkTheme = MaterialTheme(baseTextTheme).theme(darkColorScheme);

        return MaterialApp(
          navigatorKey: navigatorKey,
          theme: lightTheme,
          darkTheme: darkTheme,
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
      if (!loggedInUser!.emailVerification) {
        return EmailVerificationScreen(account: widget.account);
      }
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
                    final String? autoMemoryLanesBucket =
                        data['memoryLanesBucketId'];
                    final String? autoProfileBucket = data['profileBucketId'];

                    if (autoEndpoint != null && autoProject != null) {
                      // 1. Enforce bucket IDs for custom (self-hosted) instances
                      final bool isCustomUrl = url != AppConfig.defaultBaseUrl;
                      if (isCustomUrl &&
                          (autoMemoryLanesBucket == null ||
                              autoMemoryLanesBucket.isEmpty ||
                              autoProfileBucket == null ||
                              autoProfileBucket.isEmpty)) {
                        setState(() {
                          errorText =
                              'The self-hosted server did not return the required storage bucket configurations. Please update your backend.';
                          isLoading = false;
                        });
                        return;
                      }

                      // 2. Validate Appwrite configuration & bucket existence
                      final testClient = appwrite.Client();
                      testClient
                          .setEndpoint(autoEndpoint)
                          .setProject(autoProject)
                          .setSelfSigned(status: true);
                      final testStorage = appwrite.Storage(testClient);

                      final profileBucket = autoProfileBucket ??
                          AppConfig.defaultProfileBucketId;
                      final memoryBucket = autoMemoryLanesBucket ??
                          AppConfig.defaultMemoryLanesBucketId;

                      // Validate profile bucket
                      try {
                        await testStorage.getFile(
                          bucketId: profileBucket,
                          fileId: 'nonexistent_test_file_id',
                        );
                      } on appwrite.AppwriteException catch (e) {
                        if (e.type == 'project_not_found' ||
                            e.type == 'project_unknown') {
                          setState(() {
                            errorText =
                                'Appwrite Project ID is incorrect or not found.';
                            isLoading = false;
                          });
                          return;
                        }
                        if (e.type == 'storage_bucket_not_found') {
                          setState(() {
                            errorText =
                                'Profile picture storage bucket ($profileBucket) was not found. Please check your Appwrite configuration.';
                            isLoading = false;
                          });
                          return;
                        }
                      } catch (e) {
                        setState(() {
                          errorText =
                              'Could not connect to Appwrite endpoint: $e';
                          isLoading = false;
                        });
                        return;
                      }

                      // Validate memory lanes bucket
                      try {
                        await testStorage.getFile(
                          bucketId: memoryBucket,
                          fileId: 'nonexistent_test_file_id',
                        );
                      } on appwrite.AppwriteException catch (e) {
                        if (e.type == 'storage_bucket_not_found') {
                          setState(() {
                            errorText =
                                'Memory lanes storage bucket ($memoryBucket) was not found. Please check your Appwrite configuration.';
                            isLoading = false;
                          });
                          return;
                        }
                      } catch (e) {
                        setState(() {
                          errorText =
                              'Could not connect to Appwrite endpoint: $e';
                          isLoading = false;
                        });
                        return;
                      }

                      AppConfig.setBaseUrl(url);
                      AppConfig.setAppwriteConfig(
                        autoEndpoint,
                        autoProject,
                        memoryLanesBucket: autoMemoryLanesBucket,
                        profileBucket: autoProfileBucket,
                      );
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
                        hintText: 'https://api.aurachieve.com',
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

    setState(() => isBusy = true);
    try {
      final user = await widget.account.get();

      if (!user.emailVerification) {
        if (mounted) {
          setState(() => isBusy = false);
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(
              builder: (context) => EmailVerificationScreen(account: widget.account),
            ),
          );
        }
        return;
      }
    } catch (e) {}

    if (mounted) {
      setState(() => isBusy = false);
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

      try {
        await widget.account.createEmailVerification(
          url: 'https://aurachieve.com/verify',
        );
      } catch (e) {}

      final jwt = await widget.account.createJWT();
      await _storage.write(key: 'jwt_token', value: jwt.jwt);
      TextInput.finishAutofillContext();
      await _handleSuccessfulAuth();
    } catch (e) {
      showError('Registration failed: ${getFriendlyErrorMessage(e)}');
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
      showError('Login failed: ${getFriendlyErrorMessage(e)}');
    }
    if (mounted) {
      setState(() => isBusy = false);
    }
  }

  Future<void> _signInWithGoogle() async {
    if (!mounted) return;
    setState(() => isBusy = true);
    try {
      await widget.account.createOAuth2Session(
        provider: enums.OAuthProvider.google,
      );
      final jwt = await widget.account.createJWT();
      await _storage.write(key: 'jwt_token', value: jwt.jwt);
      await _handleSuccessfulAuth();
    } catch (e) {
      if (!e.toString().contains('canceled') &&
          !e.toString().contains('Canceled')) {
        showError('Google Sign-In failed: ${getFriendlyErrorMessage(e)}');
      }
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
                  errorText = getFriendlyErrorMessage(e);
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
    return PopScope(
      canPop: !showSignup && !showLogin,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        setState(() {
          showLogin = false;
          showSignup = false;
          stopCarousel = false;
          Future.microtask(_autoPlayFeatures);
        });
      },
      child: Scaffold(
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
                            const SizedBox(height: 16),
                            Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 24.0,
                              ),
                              child: Row(
                                children: [
                                  Expanded(child: Divider()),
                                  Padding(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 16,
                                    ),
                                    child: Text(
                                      'OR',
                                      style: GoogleFonts.gabarito(
                                        color: Theme.of(
                                          context,
                                        ).colorScheme.outline,
                                      ),
                                    ),
                                  ),
                                  Expanded(child: Divider()),
                                ],
                              ),
                            ),
                            const SizedBox(height: 16),
                            Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 24.0,
                              ),
                              child: OutlinedButton(
                                onPressed: isBusy ? null : _signInWithGoogle,
                                style: OutlinedButton.styleFrom(
                                  minimumSize: const Size(double.infinity, 56),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                ),
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    SvgPicture.asset(
                                      'assets/img/google.svg',
                                      height: 24,
                                      width: 24,
                                    ),
                                    const SizedBox(width: 12),
                                    Text(
                                      'Google',
                                      style: GoogleFonts.gabarito(fontSize: 18),
                                    ),
                                  ],
                                ),
                              ),
                            ),
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
                                        style: GoogleFonts.gabarito(
                                          fontSize: 18,
                                        ),
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
      ),
    );
  }
}

Future<void> showEmailVerificationFlow(
  BuildContext context,
  appwrite.Account account,
) async {
  EmailVerificationScreen.show(context, account);
}

String getFriendlyErrorMessage(dynamic e) {
  if (e is appwrite.AppwriteException) {
    // 1. Check specific error types first
    switch (e.type) {
      case 'user_invalid_credentials':
        return 'Incorrect email or password. Please check your credentials and try again.';
      case 'user_already_exists':
      case 'user_email_already_exists':
        return 'An account with this email address already exists. Try logging in instead.';
      case 'user_blocked':
        return 'This account has been blocked. Please contact support.';
      case 'user_not_found':
        return 'No account was found with this email address.';
      case 'user_unauthorized':
        return 'You are not authorized to perform this action. Please log in again.';
      case 'user_invalid_token':
        return 'Your session has expired or the token is invalid. Please log in again.';

      // Password policy errors
      case 'password_too_short':
        return 'Your password is too short. It must be at least 8 characters long.';
      case 'password_recently_used':
        return 'For security, you cannot reuse a recently used password.';
      case 'password_personal_data':
        return 'Your password is too weak. For security, do not use your name, email, or username in your password.';

      // General errors
      case 'general_rate_limit_exceeded':
        return 'Too many attempts. Please wait a few minutes before trying again.';
    }

    // 2. Map standard HTTP status codes
    if (e.code == 401) {
      return 'Incorrect email or password. Please check your credentials and try again.';
    } else if (e.code == 400) {
      final msg = e.message ?? '';
      if (msg.toLowerCase().contains('email')) {
        return 'Please enter a valid email address.';
      }
      if (msg.toLowerCase().contains('password')) {
        return 'Please enter a valid password (must be at least 8 characters long).';
      }
      if (msg.toLowerCase().contains('name')) {
        return 'Please enter a valid name.';
      }
      if (msg.isNotEmpty) {
        return msg.replaceAll('AppwriteException: ', '');
      }
      return 'Invalid input details. Please check your inputs and try again.';
    } else if (e.code == 403) {
      return 'Access denied. You do not have permission to perform this action.';
    } else if (e.code == 409) {
      return 'An account with this email address already exists. Try logging in instead.';
    } else if (e.code == 500 || e.code == 503) {
      return 'Server error. Please try again later.';
    }

    // 3. Fallback to raw message if available
    if (e.message != null && e.message!.isNotEmpty) {
      return e.message!.replaceAll('AppwriteException: ', '');
    }
    return 'An error occurred (Code: ${e.code}). Please try again.';
  }

  final errorStr = e.toString();
  if (errorStr.contains('NetworkImage') ||
      errorStr.contains('SocketException') ||
      errorStr.contains('Failed host lookup')) {
    return 'Network connection error. Please check your internet connection and try again.';
  }

  return errorStr
      .replaceAll('Exception: ', '')
      .replaceAll('AppwriteException: ', '');
}
