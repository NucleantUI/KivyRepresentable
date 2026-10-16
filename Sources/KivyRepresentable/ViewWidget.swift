//
//  ViewWidget.swift
//  KivyRepresentable
//
import NucleantUI
import Observation
@preconcurrency import PySwiftKit
import PySerializing
import PySwiftWrapper



/*
 Render Nucleant Views to Kivy Texture
 NucleantUI already renders to VkImage soo just a matter of using
 same trick as we are doing with Skia as providers for skia
 ```swift
 @Observable @PyClass(swift_mode: .v6)
 public final class MyPyData {
    @PyProperty var name: String
    @PyProperty var surname: String
    @PyProperty var age: Int
 
 
    
 }
 
 @View
 public struct MyView {
     
     let data: MyPyData
     
     public var body: some View {
         VStack {
             Text(data.name)
             Text(data.surname)
             Text(data.age)
         }
     }
 }
 
 
 
 
 
 ```
*/
@MainActor
@Observable
@PyClass(self_ref: true, swift_mode: .v6)
public final class ViewWidget: @preconcurrency PySerializable {
    
    private let content: () -> AnyView
    
    public init(@ViewBuilder content: @escaping () -> AnyView) {
        self.content = content
    }
    
    @MainActor public func pyPointer() -> PyPointer {
        Self.asPyPointer(unretained: self)
    }
    
    //
    
}

