// Exercise the production adapter against independently encrypted synthetic data.
#include "main.cpp"
#include <iostream>

void require(bool condition) { if (!condition) throw std::runtime_error("Vault check failed"); }
int main() {
  wchar_t directory[MAX_PATH], name[MAX_PATH];
  GetTempPathW(MAX_PATH, directory);
  if (!GetTempFileNameW(directory, L"nvt", 0, name)) return 1;
  const fs::path path(name);
  try {
    const std::string original = R"({"neutrino.flutter.fixture":"synthetic-original","unrelated":"preserve"})";
    DATA_BLOB plain{(DWORD)original.size(), (BYTE*)original.data()}, encrypted{};
    require(CryptProtectData(&plain, nullptr, nullptr, nullptr, nullptr, CRYPTPROTECT_UI_FORBIDDEN, &encrypted));
    { std::ofstream file(path, std::ios::binary); file.write((const char*)encrypted.pbData, encrypted.cbData); }
    LocalFree(encrypted.pbData);
    Vault vault(path);
    require(vault.call({{"op", "read"}, {"key", "neutrino.flutter.fixture"}}) == "synthetic-original");
    vault.call({{"op", "write"}, {"key", "neutrino.flutter.replacement"}, {"value", "synthetic-new"}});
    require(Vault(path).call({{"op", "read"}, {"key", "neutrino.flutter.replacement"}}) == "synthetic-new");
    vault.call({{"op", "delete"}, {"key", "neutrino.flutter.fixture"}});
    require(vault.call({{"op", "read"}, {"key", "neutrino.flutter.fixture"}}).is_null());
    std::ifstream file(path, std::ios::binary);
    std::string bytes((std::istreambuf_iterator<char>(file)), {}); file.close();
    require(bytes.find("synthetic-new") == std::string::npos);
    DATA_BLOB sealed{(DWORD)bytes.size(), (BYTE*)bytes.data()}, decoded{};
    require(CryptUnprotectData(&sealed, nullptr, nullptr, nullptr, nullptr, CRYPTPROTECT_UI_FORBIDDEN, &decoded));
    auto values = Json::parse(decoded.pbData, decoded.pbData + decoded.cbData);
    SecureZeroMemory(decoded.pbData, decoded.cbData); LocalFree(decoded.pbData);
    require(values.at("unrelated") == "preserve");
    { std::ofstream corrupt(path, std::ios::binary); corrupt << "invalid-dpapi"; }
    bool rejected = false;
    try { vault.call({{"op", "write"}, {"key", "neutrino.flutter.replacement"}, {"value", "new"}}); }
    catch (...) { rejected = true; }
    require(rejected);
    require(fs::file_size(path) == 13);
    fs::remove(path);
    std::cout << "PASS: DPAPI compatibility, read/write/delete, unrelated keys, no plaintext, corrupt vault preserved\n";
    return 0;
  } catch (...) {
    fs::remove(path);
    std::cerr << "FAIL: synthetic vault verification\n";
    return 1;
  }
}
