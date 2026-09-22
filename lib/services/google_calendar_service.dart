import 'dart:convert';
import 'dart:io';
import 'package:dio/dio.dart';
import 'package:url_launcher/url_launcher.dart';

class GoogleCalendarService {
  static const String _clientId =
      String.fromEnvironment('GOOGLE_CLIENT_ID');
  static const String _clientSecret =
      String.fromEnvironment('GOOGLE_CLIENT_SECRET');

  static String? _accessToken;
  final Dio _dio = Dio();

  /// Initiates a local HTTP server and drops the user into standard Google Sign In.
  /// Retrieves OAuth2 code and exchanges it for a Bearer token.
  Future<void> authenticate() async {
    if (_accessToken != null) {
      print('[GoogleCalendar] Already authenticated, skipping login.');
      return;
    }

    try {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final redirectUri = 'http://localhost:${server.port}';
      print('[GoogleCalendar] Local server started at $redirectUri');

      final authUrl = 'https://accounts.google.com/o/oauth2/v2/auth'
          '?client_id=$_clientId'
          '&redirect_uri=${Uri.encodeComponent(redirectUri)}'
          '&response_type=code'
          '&scope=https://www.googleapis.com/auth/calendar.events'
          '&access_type=offline';

      print('[GoogleCalendar] Opening browser with auth URL...');
      final launched = await launchUrl(Uri.parse(authUrl), mode: LaunchMode.externalApplication);
      print('[GoogleCalendar] launchUrl returned: $launched');

      final request = await server.first;
      final code = request.uri.queryParameters['code'];

      request.response
        ..statusCode = 200
        ..headers.contentType = ContentType.html
        ..write(
            '<html><body style="font-family:sans-serif; text-align:center; padding-top:50px;">'
            '<h1>Authentication Successful!</h1>'
            '<p>You can close this window and return to iQOO Assistant.</p>'
            '</body></html>');
      await request.response.close();
      await server.close();

      if (code == null) throw Exception('No auth code received.');

      // Exchange code for Access Token
      final tokenRes = await _dio.post(
        'https://oauth2.googleapis.com/token',
        data: {
          'code': code,
          'client_id': _clientId,
          'client_secret': _clientSecret,
          'redirect_uri': redirectUri,
          'grant_type': 'authorization_code',
        },
        options: Options(contentType: Headers.formUrlEncodedContentType),
      );

      _accessToken = tokenRes.data['access_token'];
      print('[GoogleCalendarService] Successfully acquired token: $_accessToken');
    } catch (e) {
      print('[GoogleCalendarService] Auth Error: $e');
      rethrow;
    }
  }

  /// Injects the calendar event silently via REST.
  Future<bool> scheduleEvent(String title, String startTimeIso, String endTimeIso) async {
    if (_accessToken == null) {
      await authenticate();
    }

    try {
      final res = await _dio.post(
        'https://www.googleapis.com/calendar/v3/calendars/primary/events',
        options: Options(
          headers: {'Authorization': 'Bearer $_accessToken'},
        ),
        data: {
          'summary': title,
          'start': {'dateTime': startTimeIso},
          'end': {'dateTime': endTimeIso},
        },
      );
      
      return res.statusCode == 200;
    } catch (e) {
      print('[GoogleCalendarService] Schedule Error: $e');
      return false;
    }
  }
}
