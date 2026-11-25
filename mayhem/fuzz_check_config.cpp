// Fuzz preCICE's configuration validator: the public precice::tooling::checkConfiguration(),
// exactly what the `precice-config-validate FILE` CLI runs. The input is a precice-config.xml:
// libxml2 SAX -> xml::ConfigParser -> XMLTag attribute parsing -> every *Configuration class.
// A rejected configuration throws precice::Error (the CLI maps that to exit 2), so it is caught.
#include <precice/Exceptions.hpp>
#include <precice/Tooling.hpp>
#include "fuzz_common.hpp"

extern "C" int LLVMFuzzerInitialize(int *, char ***)
{
  mayhem_fuzz::silenceStdout();
  return 0;
}

extern "C" int LLVMFuzzerTestOneInput(const uint8_t *data, size_t size)
{
  const std::string path = mayhem_fuzz::writeInput(data, size);
  try {
    // No participant and a single rank, as `precice-config-validate FILE` does.
    precice::tooling::checkConfiguration(path, "", 1);
  } catch (const precice::Error &) {
  }
  unlink(path.c_str());
  return 0;
}
