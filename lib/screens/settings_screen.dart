import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/api_service.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  static String _memoryApiKey = '';

  final _serverUrlController = TextEditingController();
  final _tokenController = TextEditingController();
  final _apiKeyController = TextEditingController();
  final _apiBaseController = TextEditingController();
  final _modelController = TextEditingController();
  final _temperatureController = TextEditingController(text: '0.7');
  final _maxTokensController = TextEditingController(text: '4096');

  String _selectedProvider = 'OpenAI';

  static const List<String> _providers = [
    'OpenAI',
    'Anthropic',
    'Azure',
    'Ollama',
    'Google',
    '自定义',
  ];

  static const Map<String, String> _providerDefaults = {
    'OpenAI': 'https://api.openai.com/v1',
    'Anthropic': 'https://api.anthropic.com/v1',
    'Azure': 'https://YOUR_RESOURCE.openai.azure.com',
    'Ollama': 'http://localhost:11434/v1',
    'Google': 'https://generativelanguage.googleapis.com/v1',
    '自定义': '',
  };

  bool _isTesting = false;
  bool? _connectionStatus;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    _serverUrlController.text = prefs.getString('server_url') ?? 'http://10.10.10.200:8001';
    _tokenController.text = prefs.getString('api_token') ?? 'simon123';
    // API Key is NOT persisted to disk — static variable, survives app restart (intentional security)
    _apiKeyController.text = _memoryApiKey;
    _apiBaseController.text = prefs.getString('llm_api_base') ?? 'http://10.10.10.22:8317/v1';
    _modelController.text = prefs.getString('llm_model') ?? 'deepseek-v4-flash';
    _temperatureController.text = (prefs.getDouble('llm_temperature') ?? 0.7).toString();
    _maxTokensController.text = (prefs.getInt('llm_max_tokens') ?? 4096).toString();
    _selectedProvider = prefs.getString('llm_provider') ?? 'OpenAI';
    setState(() {});
  }

  Future<void> _saveSettings() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('server_url', _serverUrlController.text.trim());
    await prefs.setString('api_token', _tokenController.text.trim());
    // ⚠️ API Key is NOT saved to disk — only kept in static memory (lost on app restart, intentional security)
    _memoryApiKey = _apiKeyController.text.trim();
    await prefs.setString('llm_api_base', _apiBaseController.text.trim());
    await prefs.setString('llm_model', _modelController.text.trim());
    await prefs.setDouble('llm_temperature', double.tryParse(_temperatureController.text) ?? 0.7);
    await prefs.setInt('llm_max_tokens', int.tryParse(_maxTokensController.text) ?? 4096);
    await prefs.setString('llm_provider', _selectedProvider);

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('设置已保存')),
      );
    }
  }

  void _onProviderChanged(String? provider) {
    if (provider == null) return;
    setState(() {
      _selectedProvider = provider;
      // Auto-fill base URL if not customized
      final currentBase = _apiBaseController.text.trim();
      final defaults = _providerDefaults[provider] ?? '';
      if (defaults.isNotEmpty && currentBase.isEmpty) {
        _apiBaseController.text = defaults;
      }
      // Auto-fill model name based on provider
      if (provider == 'OpenAI' && _modelController.text.isEmpty) {
        _modelController.text = 'gpt-4o';
      } else if (provider == 'Anthropic' && _modelController.text.isEmpty) {
        _modelController.text = 'claude-sonnet-4';
      } else if (provider == 'Ollama' && _modelController.text.isEmpty) {
        _modelController.text = 'llama3';
      } else if (provider == 'Google' && _modelController.text.isEmpty) {
        _modelController.text = 'gemini-2.0-flash';
      }
    });
  }

  Future<void> _testConnection() async {
    setState(() {
      _isTesting = true;
      _connectionStatus = null;
    });

    final api = ApiService(
      baseUrl: _serverUrlController.text.trim(),
      token: _tokenController.text.trim(),
    );

    final ok = await api.healthCheck();

    setState(() {
      _isTesting = false;
      _connectionStatus = ok;
    });

    api.dispose();
  }

  Future<void> _configureLLM() async {
    final api = ApiService(
      baseUrl: _serverUrlController.text.trim(),
      token: _tokenController.text.trim(),
    );

    final ok = await api.configureLLM(
      apiKey: _memoryApiKey.isNotEmpty ? _memoryApiKey : _apiKeyController.text.trim(),
      apiBase: _apiBaseController.text.trim(),
      model: _modelController.text.trim(),
      temperature: double.tryParse(_temperatureController.text),
      maxTokens: int.tryParse(_maxTokensController.text),
    );

    api.dispose();

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(ok ? 'LLM 配置已下发到服务器' : '下发失败，请检查连接'),
          backgroundColor: ok ? Colors.green : Colors.red,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('设置'),
        actions: [
          TextButton(
            onPressed: _saveSettings,
            child: const Text('保存'),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Server Section
          _sectionTitle('服务器'),
          _textField(_serverUrlController, '服务器地址', 'http://10.10.10.200:8001'),
          const SizedBox(height: 8),
          _textField(_tokenController, 'API Token', 'ga-dev-token-change-me', obscure: true),
          const SizedBox(height: 8),
          Row(
            children: [
              ElevatedButton.icon(
                onPressed: _isTesting ? null : _testConnection,
                icon: _isTesting
                    ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                    : Icon(
                        _connectionStatus == null
                            ? Icons.wifi_find
                            : _connectionStatus!
                                ? Icons.wifi
                                : Icons.wifi_off,
                        size: 18,
                      ),
                label: Text(_isTesting ? '测试中...' : '测试连接'),
              ),
              if (_connectionStatus != null) ...[
                const SizedBox(width: 8),
                Icon(
                  _connectionStatus! ? Icons.check_circle : Icons.error,
                  color: _connectionStatus! ? Colors.green : Colors.red,
                ),
              ],
            ],
          ),

          const SizedBox(height: 24),

          // LLM Section
          _sectionTitle('LLM 配置'),
          
          // Provider dropdown
          DropdownButtonFormField<String>(
            initialValue: _selectedProvider,
            decoration: const InputDecoration(
              labelText: 'Provider',
              border: OutlineInputBorder(),
              isDense: true,
            ),
            items: _providers.map((p) {
              return DropdownMenuItem(value: p, child: Text(p));
            }).toList(),
            onChanged: _onProviderChanged,
          ),
          const SizedBox(height: 8),

          _textField(_apiKeyController, 'API Key', 'sk-...', obscure: true),
          const SizedBox(height: 8),
          _textField(_apiBaseController, 'Base URL', _providerDefaults[_selectedProvider] ?? ''),
          const SizedBox(height: 8),
          _textField(_modelController, '模型', 'gpt-4o'),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(child: _textField(_temperatureController, '温度', '0.7')),
              const SizedBox(width: 8),
              Expanded(child: _textField(_maxTokensController, '最大 Token', '4096')),
            ],
          ),
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: _configureLLM,
              icon: const Icon(Icons.cloud_upload, size: 18),
              label: const Text('应用到服务器'),
            ),
          ),

          const SizedBox(height: 24),

          // Info
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('安全提示', style: TextStyle(fontWeight: FontWeight.bold, color: Theme.of(context).colorScheme.primary)),
                const SizedBox(height: 4),
                Text(
                  'API Key 不会保存到手机存储中，仅保存在内存里。重启 APP 后需要重新输入。\n'
                  '通过 /v1/config/llm 接口下发到 NAS 服务器内存中，不会落盘。',
                  style: TextStyle(fontSize: 13, color: Colors.grey[600]),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _sectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        title,
        style: TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.w600,
          color: Theme.of(context).colorScheme.primary,
        ),
      ),
    );
  }

  Widget _textField(TextEditingController ctrl, String label, String hint, {bool obscure = false}) {
    return TextField(
      controller: ctrl,
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        border: const OutlineInputBorder(),
        isDense: true,
      ),
      obscureText: obscure,
    );
  }

  @override
  void dispose() {
    _serverUrlController.dispose();
    _tokenController.dispose();
    _apiKeyController.dispose();
    _apiBaseController.dispose();
    _modelController.dispose();
    _temperatureController.dispose();
    _maxTokensController.dispose();
    super.dispose();
  }
}