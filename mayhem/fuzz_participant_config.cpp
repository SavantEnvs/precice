// Fuzz preCICE participant construction: precice::Participant("SolverOne", configFile, 0, 1).
// The constructor parses the configuration (same XML front end as checkConfiguration) and then
// runs ParticipantImpl::configure: mesh/partition setup, mappings, exporters, watch points,
// actions, intra-participant communication and m2n setup, then destruction/finalization.
// initialize() is never called (it would block waiting for the coupled peer).
// Invalid configurations throw precice::Error, which is caught.
#include <precice/Exceptions.hpp>
#include <precice/Participant.hpp>
#include "fuzz_common.hpp"

extern "C" int LLVMFuzzerInitialize(int *, char ***)
{
  mayhem_fuzz::silenceStdout();
  return 0;
}

extern "C" int LLVMFuzzerTestOneInput(const uint8_t *data, size_t size)
{
  const std::string path = mayhem_fuzz::writeInput(data, size);
  {
    // The Participant's file outputs (watch points, log file sinks, profiling) go to a per-input
    // scratch cwd that is removed afterwards; see ScratchCwd in fuzz_common.hpp.
    mayhem_fuzz::ScratchCwd scratch;
    try {
      // "SolverOne" is the participant name used by upstream's serial integration-test configs,
      // which are this target's seeds; a config without that participant is rejected by preCICE.
      precice::Participant participant("SolverOne", path, 0, 1);
    } catch (const precice::Error &) {
    }
  }
  unlink(path.c_str());
  return 0;
}
