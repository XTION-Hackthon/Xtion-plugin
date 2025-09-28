//
//  AudioController.swift
//  Xtion-plugin
//
//  Created by GH on 9/28/25.
//

import CoreAudio

@MainActor
class AudioController {
    private let deviceID: AudioDeviceID
    private var outputAddress = AudioObjectPropertyAddress(
        mSelector: kAudioDevicePropertyVolumeScalar,
        mScope: kAudioDevicePropertyScopeOutput,
        mElement: kAudioObjectPropertyElementMain
    )
    private var muteAddress = AudioObjectPropertyAddress(
        mSelector: kAudioDevicePropertyMute,
        mScope: kAudioDevicePropertyScopeOutput,
        mElement: kAudioObjectPropertyElementMain
    )
    
    init() {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var deviceID = AudioDeviceID(0)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        
        AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &deviceID)
        self.deviceID = deviceID
    }
    
    func setVolume(_ volume: Float32) {
        var vol = volume
        AudioObjectSetPropertyData(deviceID, &outputAddress, 0, nil, UInt32(MemoryLayout<Float32>.size), &vol)
    }
    
    func setMute(_ shouldMute: Bool) {
        var muteValue: UInt32 = shouldMute ? 1 : 0
        AudioObjectSetPropertyData(deviceID, &muteAddress, 0, nil, UInt32(MemoryLayout<UInt32>.size), &muteValue)
    }
    
    func unmuteIfMuted() {
        var currentMute: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        AudioObjectGetPropertyData(deviceID, &muteAddress, 0, nil, &size, &currentMute)
        if currentMute == 1 {
            setMute(false)
        }
    }
}
