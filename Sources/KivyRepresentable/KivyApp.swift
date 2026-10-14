//
//  KivyApp.swift
//  KivyRepresentable
//
//  A `NucleantApp` whose windows render with `KivyRenderNode`.
//

import NucleantUI

public protocol KivyApp: NucleantApp where RenderNode == KivyRenderNode {}
