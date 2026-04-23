import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../controllers/auth_controller.dart';

class SignupScreen extends StatefulWidget {
  const SignupScreen({super.key});

  @override
  State<SignupScreen> createState() => _SignupScreenState();
}

class _SignupScreenState extends State<SignupScreen> {
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _phoneController = TextEditingController();
  final _ec1Controller = TextEditingController();
  final _ec2Controller = TextEditingController();

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _phoneController.dispose();
    _ec1Controller.dispose();
    _ec2Controller.dispose();
    super.dispose();
  }

  Future<void> _signUp() async {
    if (_nameController.text.isEmpty || _emailController.text.isEmpty || _passwordController.text.isEmpty || _phoneController.text.isEmpty || _ec1Controller.text.isEmpty || _ec2Controller.text.isEmpty) {
      Get.snackbar("Error", "All fields are required", backgroundColor: Colors.redAccent, colorText: Colors.white);
      return;
    }
    await AuthController.instance.register(
      _nameController.text.trim(),
      _emailController.text.trim(),
      _passwordController.text.trim(),
      _phoneController.text.trim(),
      _ec1Controller.text.trim(),
      _ec2Controller.text.trim()
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Create Account")),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          children: [
            TextField(controller: _nameController, decoration: const InputDecoration(labelText: 'Full Name', border: OutlineInputBorder(), prefixIcon: Icon(Icons.person))),
            const SizedBox(height: 16),
            TextField(controller: _emailController, decoration: const InputDecoration(labelText: 'Email', border: OutlineInputBorder(), prefixIcon: Icon(Icons.email)), keyboardType: TextInputType.emailAddress),
            const SizedBox(height: 16),
            TextField(controller: _passwordController, decoration: const InputDecoration(labelText: 'Password', border: OutlineInputBorder(), prefixIcon: Icon(Icons.lock)), obscureText: true),
            const SizedBox(height: 16),
            TextField(controller: _phoneController, decoration: const InputDecoration(labelText: 'Phone Number', border: OutlineInputBorder(), prefixIcon: Icon(Icons.phone)), keyboardType: TextInputType.phone),
            const SizedBox(height: 16),
            const Divider(),
            const Text("Emergency Contacts", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 16),
            TextField(controller: _ec1Controller, decoration: const InputDecoration(labelText: 'Contact 1', border: OutlineInputBorder(), prefixIcon: Icon(Icons.contact_phone)), keyboardType: TextInputType.phone),
            const SizedBox(height: 16),
            TextField(controller: _ec2Controller, decoration: const InputDecoration(labelText: 'Contact 2', border: OutlineInputBorder(), prefixIcon: Icon(Icons.contact_phone)), keyboardType: TextInputType.phone),
            const SizedBox(height: 32),
            SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton(
                onPressed: _signUp,
                child: const Text('Register & Sync', style: TextStyle(fontSize: 18)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
