//
//  WireMessageType.swift
//  MultiView
//
//  Created by Brendan Lensink on 2026-06-08.
//

enum WireMessageType: UInt8 {
    case frame = 0x01
    case syncPing = 0x02
    case syncPong = 0x03
}
