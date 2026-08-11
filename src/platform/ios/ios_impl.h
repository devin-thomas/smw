#pragma once

#include <stdbool.h>
#include <stdint.h>

enum IosImplAction {
  kIosImplActionReset = 1u << 0,
  kIosImplActionSaveState = 1u << 1,
  kIosImplActionLoadState = 1u << 2,
  kIosImplActionQuit = 1u << 3,
};

#ifdef __cplusplus
extern "C" {
#endif

bool IosImpl_PrepareRuntime(void);
void IosImpl_ConfigureAudioSession(void);
void IosImpl_SetAudioSessionActive(bool active);
void IosImpl_InstallTouchControls(void);
void IosImpl_SetControllerConnected(bool connected);
void IosImpl_ReleaseAllInputs(void);
uint32_t IosImpl_GetTouchInput(void);
uint32_t IosImpl_TakePendingActions(void);

#ifdef __cplusplus
}
#endif
