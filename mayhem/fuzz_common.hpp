// Shared helpers for the preCICE config harnesses (mayhem/ only, not upstream code).
#pragma once
#include <cstdint>
#include <cstdio>
#include <cstdlib>
#include <fcntl.h>
#include <filesystem>
#include <string>
#include <system_error>
#include <unistd.h>

namespace mayhem_fuzz {

// preCICE's public API only accepts a configuration FILE NAME, so each input is written to a
// fresh scratch file under $TMPDIR (default /tmp), passed by path, and removed afterwards.
inline std::string writeInput(const uint8_t *data, size_t size)
{
  const char *tmp = std::getenv("TMPDIR");
  std::string path = std::string((tmp && *tmp) ? tmp : "/tmp") + "/precice-fuzz-XXXXXX.xml";
  int fd = mkstemps(&path[0], 4);
  if (fd < 0)
    std::abort();
  size_t off = 0;
  while (off < size) {
    ssize_t n = write(fd, data + off, size - off);
    if (n <= 0)
      std::abort();
    off += static_cast<size_t>(n);
  }
  close(fd);
  return path;
}

// A per-input scratch working directory: a fresh mkdtemp() dir under $TMPDIR (default /tmp) that
// becomes the cwd while the input runs, then the old cwd is restored and the dir is removed
// recursively. Everything a configuration writes to a relative path (watch-point/watch-integral
// .txt tables, <log><sink type="file"> outputs, <profiling directory=...>, and the default
// precice-profiling/ the Participant destructor writes) lands here and is gone before the next
// input, so no input sees files an earlier one created. Absolute output paths are not confined.
class ScratchCwd {
public:
  ScratchCwd()
  {
    const char *tmp = std::getenv("TMPDIR");
    std::string tmpl = std::string((tmp && *tmp) ? tmp : "/tmp") + "/precice-fuzz-cwd-XXXXXX";
    if (!mkdtemp(&tmpl[0]))
      std::abort();
    dir_ = tmpl;
    std::error_code ec;
    old_ = std::filesystem::current_path(ec);
    if (ec || chdir(dir_.c_str()) != 0)
      std::abort();
  }
  ~ScratchCwd()
  {
    if (chdir(old_.c_str()) != 0)
      std::abort();
    std::error_code ec;
    std::filesystem::remove_all(dir_, ec);
  }
  ScratchCwd(const ScratchCwd &)            = delete;
  ScratchCwd &operator=(const ScratchCwd &) = delete;

private:
  std::string           dir_;
  std::filesystem::path old_;
};

// preCICE logs every configuration step to stdout; silence it (libFuzzer and the sanitizers
// report on stderr, which stays untouched).
inline void silenceStdout()
{
  int fd = open("/dev/null", O_WRONLY);
  if (fd >= 0) {
    dup2(fd, 1);
    close(fd);
  }
}

} // namespace mayhem_fuzz
