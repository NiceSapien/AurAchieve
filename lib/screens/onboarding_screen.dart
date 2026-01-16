import 'package:flutter/material.dart';
import 'package:appwrite/appwrite.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../widgets/dynamic_color_svg.dart';
import '../home.dart';

class AuraOnboarding extends StatefulWidget {
  final Account account;
  const AuraOnboarding({super.key, required this.account});

  @override
  State<AuraOnboarding> createState() => _AuraOnboardingState();
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

  @override
  void initState() {
    super.initState();
    Future.microtask(_autoPlayFeatures);
  }

  void _autoPlayFeatures() async {
    const int featureCount = 3;
    while (mounted && !stopCarousel) {
      await Future.delayed(const Duration(seconds: 3));
      if (!mounted || stopCarousel) break;
      int next = (_featurePage + 1) % featureCount;
      if (_featureController.hasClients) {
        _featureController.animateToPage(
          next,
          duration: Duration(milliseconds: 400),
          curve: Curves.easeInOut,
        );
      }
    }
  }

  void showError(String msg) {
    if (!mounted) return;
    setState(() => error = msg);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: Colors.red.shade400),
    );
  }

  Future<void> register() async {
    setState(() => isBusy = true);
    try {
      await widget.account.create(
        userId: ID.unique(),
        email: emailController.text.trim(),
        password: passwordController.text,
        name: nameController.text.trim(),
      );
      await login();
    } catch (e) {
      showError(
        'Registration failed: ${e.toString().replaceAll('AppwriteException: ', '')}',
      );
      if (mounted) setState(() => isBusy = false);
    }
  }

  Future<void> login() async {
    if (!mounted) {
      setState(() => isBusy = true);
    } else {
      isBusy = true;
    }

    try {
      await widget.account.createEmailPasswordSession(
        email: emailController.text.trim(),
        password: passwordController.text,
      );
      final jwt = await widget.account.createJWT();
      await _storage.write(key: 'jwt_token', value: jwt.jwt);

      if (mounted) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (context) => HomePage(account: widget.account),
          ),
        );
      }
    } catch (e) {
      showError(
        'Login failed: ${e.toString().replaceAll('AppwriteException: ', '')}',
      );
    }
    if (mounted) {
      setState(() => isBusy = false);
    }
  }

  Widget _authHeader({required bool isSignup}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 32.0, horizontal: 24.0),
      child: Column(
        children: [
          SizedBox(
            height: 150,
            child: DynamicColorSvg(
              assetName: 'assets/img/welcome.svg',
              color: Theme.of(context).colorScheme.primary,
              fit: BoxFit.contain,
            ),
          ),
          SizedBox(height: 24),
          Text(
            isSignup ? 'Welcome Aboard!' : 'Welcome Back!',
            style: GoogleFonts.ebGaramond(
              fontSize: 32,
              fontWeight: FontWeight.bold,
              color: Theme.of(context).colorScheme.primary,
            ),
            textAlign: TextAlign.center,
          ),
          SizedBox(height: 8),
          Text(
            isSignup ? 'Let\'s get you started.' : 'Continue your journey.',
            style: GoogleFonts.gabarito(
              fontSize: 18,
              color: Theme.of(context).colorScheme.secondary,
            ),
            textAlign: TextAlign.center,
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
        'title': 'Aura Points',
        'desc': 'Earn and track your Aura as you complete tasks.',
      },
      {
        'svg': 'assets/img/feature2.svg',
        'title': 'AI Powered',
        'desc': 'Let AI verify your progress and help you grow.',
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
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24.0),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          TextField(
            controller: nameController,
            decoration: InputDecoration(
              labelText: 'Name',
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            style: TextStyle(color: Theme.of(context).colorScheme.onSurface),
          ),
          SizedBox(height: 16),
          TextField(
            controller: emailController,
            decoration: InputDecoration(
              labelText: 'Email',
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            keyboardType: TextInputType.emailAddress,
            style: TextStyle(color: Theme.of(context).colorScheme.onSurface),
          ),
          SizedBox(height: 16),
          TextField(
            controller: passwordController,
            decoration: InputDecoration(
              labelText: 'Password',
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            obscureText: true,
            style: TextStyle(color: Theme.of(context).colorScheme.onSurface),
          ),
          SizedBox(height: 24),
          if (error.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 16.0),
              child: Text(
                error,
                style: TextStyle(color: Colors.red.shade400, fontSize: 14),
              ),
            ),
          isBusy
              ? CircularProgressIndicator()
              : FilledButton.icon(
                  icon: Icon(Icons.person_add_alt_1_rounded),
                  onPressed: register,
                  label: Text(
                    'Sign Up',
                    style: GoogleFonts.gabarito(fontSize: 18),
                  ),
                  style: FilledButton.styleFrom(
                    minimumSize: Size(double.infinity, 48),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                ),
          SizedBox(height: 16),
          TextButton(
            onPressed: () => setState(() {
              showSignup = false;
              showLogin = true;
              error = '';
            }),
            child: Text('Already have an account? Login'),
          ),
        ],
      ),
    );
  }

  Widget _loginForm() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24.0),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          TextField(
            controller: emailController,
            decoration: InputDecoration(
              labelText: 'Email',
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            keyboardType: TextInputType.emailAddress,
            style: TextStyle(color: Theme.of(context).colorScheme.onSurface),
          ),
          SizedBox(height: 16),
          TextField(
            controller: passwordController,
            decoration: InputDecoration(
              labelText: 'Password',
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            obscureText: true,
            style: TextStyle(color: Theme.of(context).colorScheme.onSurface),
          ),
          SizedBox(height: 24),
          if (error.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 16.0),
              child: Text(
                error,
                style: TextStyle(color: Colors.red.shade400, fontSize: 14),
              ),
            ),
          isBusy
              ? CircularProgressIndicator()
              : FilledButton.icon(
                  icon: Icon(Icons.login_rounded),
                  onPressed: login,
                  label: Text(
                    'Login',
                    style: GoogleFonts.gabarito(fontSize: 18),
                  ),
                  style: FilledButton.styleFrom(
                    minimumSize: Size(double.infinity, 48),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                ),
          SizedBox(height: 16),
          TextButton(
            onPressed: () => setState(() {
              showLogin = false;
              showSignup = true;
              error = '';
            }),
            child: Text('Don\'t have an account? Sign Up'),
          ),
        ],
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
              currentScreen = Column(
                key: ValueKey('carousel'),
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
                            error = '';
                          }),
                          label: Text(
                            'Get Started',
                            style: GoogleFonts.gabarito(fontSize: 18),
                          ),
                          style: FilledButton.styleFrom(
                            minimumSize: Size(double.infinity, 48),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16),
                            ),
                          ),
                        ),
                        SizedBox(height: 16),
                        OutlinedButton.icon(
                          icon: Icon(Icons.login_rounded),
                          onPressed: () => setState(() {
                            showLogin = true;
                            stopCarousel = true;
                            error = '';
                          }),
                          label: Text(
                            'Login',
                            style: GoogleFonts.gabarito(fontSize: 18),
                          ),
                          style: OutlinedButton.styleFrom(
                            minimumSize: Size(double.infinity, 48),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              );
            } else {
              currentScreen = SingleChildScrollView(
                key: ValueKey('form'),
                padding: EdgeInsets.only(
                  bottom: MediaQuery.of(context).viewInsets.bottom > 0
                      ? MediaQuery.of(context).viewInsets.bottom + 16
                      : 16.0,
                  top: 16.0,
                ),
                child: Column(
                  children: [
                    _authHeader(isSignup: showSignup),
                    formWidget ?? SizedBox.shrink(),
                  ],
                ),
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
