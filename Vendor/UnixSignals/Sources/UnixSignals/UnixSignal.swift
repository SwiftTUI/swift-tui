// © OPTIONAL.DEV

//===----------------------------------------------------------------------===//
//
// This source file is part of the SwiftServiceLifecycle open source project
//
// Copyright (c) 2023 Apple Inc. and the SwiftServiceLifecycle project authors
// Licensed under Apache License v2.0
//
// See LICENSE.txt for license information
// See CONTRIBUTORS.txt for the list of SwiftServiceLifecycle project authors
//
// SPDX-License-Identifier: Apache-2.0
//
//===----------------------------------------------------------------------===//

@_exported public import SwiftTUIPlatformIO

/// Compatibility spelling for the framework-owned terminal signal value.
/// Existing explicitly typed signal arrays remain source-compatible.
public typealias UnixSignal = TerminalSignal
