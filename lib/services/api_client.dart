import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../config/config_url.dart';

class ApiClient {
  final String baseUrl;

  ApiClient({String? baseUrl}) : baseUrl = baseUrl ?? Config_URL.baseUrl;

  Future<Map<String, String>> _buildHeaders(Map<String, String>? customHeaders) async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    String? token = prefs.getString('jwt_token');

    return {
      'Content-Type': 'application/json',
      if (token != null && token.isNotEmpty) 'Authorization': 'Bearer $token',
      if (customHeaders != null) ...customHeaders,
    };
  }

  Future<http.Response> get(String endpoint, {Map<String, String>? headers}) async {
    final mergedHeaders = await _buildHeaders(headers);
    return http.get(
      Uri.parse('$baseUrl$endpoint'),
      headers: mergedHeaders,
    );
  }

  Future<http.Response> post(String endpoint, {Map<String, String>? headers, dynamic body}) async {
    final mergedHeaders = await _buildHeaders(headers);
    return http.post(
      Uri.parse('$baseUrl$endpoint'),
      headers: mergedHeaders,
      body: jsonEncode(body),
    );
  }

  Future<http.Response> put(String endpoint, {Map<String, String>? headers, dynamic body}) async {
    final mergedHeaders = await _buildHeaders(headers);
    return http.put(
      Uri.parse('$baseUrl$endpoint'),
      headers: mergedHeaders,
      body: jsonEncode(body),
    );
  }

  Future<http.Response> delete(String endpoint, {Map<String, String>? headers}) async {
    final mergedHeaders = await _buildHeaders(headers);
    return http.delete(
      Uri.parse('$baseUrl$endpoint'),
      headers: mergedHeaders,
    );
  }
}