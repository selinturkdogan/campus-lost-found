import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/auth_provider.dart';
import '../../utils/app_routes.dart';
import '../../utils/app_theme.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen>
    with TickerProviderStateMixin {
  final _formKey = GlobalKey<FormState>();
  final _emailCtrl = TextEditingController();
  final _passCtrl = TextEditingController();
  bool _obscurePassword = true;

  late final AnimationController _entryCtrl;
  late final List<Animation<Offset>> _slideAnims;
  late final List<Animation<double>> _fadeAnims;

  @override
  void initState() {
    super.initState();
    _entryCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );

    _slideAnims = List.generate(5, (i) {
      return Tween<Offset>(
        begin: const Offset(0, 0.3),
        end: Offset.zero,
      ).animate(CurvedAnimation(
        parent: _entryCtrl,
        curve: Interval(i * 0.1, 0.6 + i * 0.1, curve: Curves.easeOutCubic),
      ));
    });

    _fadeAnims = List.generate(5, (i) {
      return Tween<double>(begin: 0, end: 1).animate(CurvedAnimation(
        parent: _entryCtrl,
        curve: Interval(i * 0.1, 0.6 + i * 0.1, curve: Curves.easeOut),
      ));
    });

    _entryCtrl.forward();
  }

  @override
  void dispose() {
    _entryCtrl.dispose();
    _emailCtrl.dispose();
    _passCtrl.dispose();
    super.dispose();
  }

  Future<void> _login() async {
    if (!_formKey.currentState!.validate()) return;
    final auth = context.read<AuthProvider>();
    final success = await auth.login(
      email: _emailCtrl.text.trim(),
      password: _passCtrl.text,
    );
    if (!mounted) return;
    if (success) {
      Navigator.pushReplacementNamed(context, AppRoutes.feed);
    } else {
      _showError(auth.errorMessage ?? 'Login failed');
    }
  }

  Future<void> _loginWithGoogle() async {
    final auth = context.read<AuthProvider>();
    final success = await auth.signInWithGoogle();
    if (!mounted) return;
    if (success) {
      Navigator.pushReplacementNamed(context, AppRoutes.feed);
    } else if (auth.errorMessage != null) {
      _showError(auth.errorMessage!);
    }
  }

  void _showError(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.error_outline_rounded, color: Color(0xFFFF6B6B), size: 18),
            const SizedBox(width: 10),
            Expanded(child: Text(msg)),
          ],
        ),
        backgroundColor: Theme.of(context).colorScheme.surfaceVariant,
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.all(16),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }

  Widget _animated(int i, Widget child) {
    return FadeTransition(
      opacity: _fadeAnims[i],
      child: SlideTransition(position: _slideAnims[i], child: child),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: isDark ? AppTheme.darkBgGradient : null,
          color: isDark ? null : scheme.surface,
        ),
        child: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 28),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 56),

                  _animated(
                    0,
                    Container(
                      width: 60,
                      height: 60,
                      decoration: BoxDecoration(
                        gradient: AppTheme.primaryGradient,
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: const Icon(Icons.search_rounded, color: Colors.white, size: 30),
                    ),
                  ),

                  const SizedBox(height: 28),

                  _animated(
                    1,
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Welcome back', style: textTheme.displayMedium),
                        const SizedBox(height: 8),
                        Text(
                          'Sign in with your university account to continue.',
                          style: textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 40),

                  _animated(
                    2,
                    Column(
                      children: [
                        _buildLabel('Email address'),
                        const SizedBox(height: 8),
                        TextFormField(
                          controller: _emailCtrl,
                          keyboardType: TextInputType.emailAddress,
                          textInputAction: TextInputAction.next,
                          style: textTheme.bodyLarge,
                          decoration: InputDecoration(
                            hintText: 'you@university.edu',
                            prefixIcon: Icon(Icons.email_outlined, size: 20, color: scheme.onSurfaceVariant),
                          ),
                          validator: (val) {
                            if (val == null || val.isEmpty) return 'Email is required';
                            if (!val.contains('@')) return 'Enter a valid email';
                            return null;
                          },
                        ),
                        const SizedBox(height: 20),
                        _buildLabel('Password'),
                        const SizedBox(height: 8),
                        TextFormField(
                          controller: _passCtrl,
                          obscureText: _obscurePassword,
                          textInputAction: TextInputAction.done,
                          onFieldSubmitted: (_) => _login(),
                          style: textTheme.bodyLarge,
                          decoration: InputDecoration(
                            hintText: '••••••••',
                            prefixIcon: Icon(Icons.lock_outline_rounded, size: 20, color: scheme.onSurfaceVariant),
                            suffixIcon: IconButton(
                              icon: Icon(
                                _obscurePassword ? Icons.visibility_outlined : Icons.visibility_off_outlined,
                                size: 20,
                                color: scheme.onSurfaceVariant,
                              ),
                              onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
                            ),
                          ),
                          validator: (val) {
                            if (val == null || val.isEmpty) return 'Password is required';
                            if (val.length < 6) return 'Password must be at least 6 characters';
                            return null;
                          },
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 32),

                  _animated(
                    3,
                    Consumer<AuthProvider>(
                      builder: (_, auth, __) => _GradientButton(
                        label: 'Sign in',
                        isLoading: auth.isLoading,
                        onTap: _login,
                      ),
                    ),
                  ),

                  const SizedBox(height: 16),

                  // OR divider
                  _animated(
                    4,
                    Column(
                      children: [
                        Row(
                          children: [
                            Expanded(child: Divider(color: scheme.outline)),
                            Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 12),
                              child: Text('or', style: textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant)),
                            ),
                            Expanded(child: Divider(color: scheme.outline)),
                          ],
                        ),
                        const SizedBox(height: 16),

                        // Google Sign-In button
                        Consumer<AuthProvider>(
                          builder: (_, auth, __) => GestureDetector(
                            onTap: auth.isLoading ? null : _loginWithGoogle,
                            child: Container(
                              width: double.infinity,
                              height: 52,
                              decoration: BoxDecoration(
                                color: scheme.surface,
                                borderRadius: BorderRadius.circular(14),
                                border: Border.all(color: scheme.outline),
                              ),
                              child: auth.isLoading
                                  ? const Center(child: SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2)))
                                  : Row(
                                      mainAxisAlignment: MainAxisAlignment.center,
                                      children: [
                                        Image.asset('assets/images/google_logo.png', width: 22, height: 22,
                                          errorBuilder: (_, __, ___) => const Icon(Icons.g_mobiledata_rounded, size: 24),
                                        ),
                                        const SizedBox(width: 10),
                                        Text(
                                          'Continue with Google',
                                          style: textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.w600),
                                        ),
                                      ],
                                    ),
                            ),
                          ),
                        ),

                        const SizedBox(height: 24),

                        Container(
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: scheme.surfaceVariant,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: scheme.outline),
                          ),
                          child: Row(
                            children: [
                              Icon(Icons.info_outline_rounded, size: 16, color: scheme.onSurfaceVariant),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  'Sign in with your university Google account.',
                                  style: textTheme.bodySmall,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 40),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildLabel(String text) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Text(
        text,
        style: Theme.of(context).textTheme.labelLarge?.copyWith(
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
}

class _GradientButton extends StatefulWidget {
  final String label;
  final bool isLoading;
  final VoidCallback onTap;

  const _GradientButton({required this.label, required this.isLoading, required this.onTap});

  @override
  State<_GradientButton> createState() => _GradientButtonState();
}

class _GradientButtonState extends State<_GradientButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pressCtrl;
  late final Animation<double> _scaleAnim;

  @override
  void initState() {
    super.initState();
    _pressCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 120),
      lowerBound: 0.95,
      upperBound: 1.0,
      value: 1.0,
    );
    _scaleAnim = _pressCtrl;
  }

  @override
  void dispose() {
    _pressCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => _pressCtrl.reverse(),
      onTapUp: (_) {
        _pressCtrl.forward();
        if (!widget.isLoading) widget.onTap();
      },
      onTapCancel: () => _pressCtrl.forward(),
      child: ScaleTransition(
        scale: _scaleAnim,
        child: Container(
          width: double.infinity,
          height: 52,
          decoration: BoxDecoration(
            gradient: AppTheme.primaryGradient,
            borderRadius: BorderRadius.circular(14),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF7C3AED).withOpacity(0.35),
                blurRadius: 20,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: widget.isLoading
              ? const Center(child: SizedBox(width: 22, height: 22, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2)))
              : Center(
                  child: Text(
                    widget.label,
                    style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w600, letterSpacing: 0.2),
                  ),
                ),
        ),
      ),
    );
  }
}