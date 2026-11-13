import AppKit
import SwiftUI

@main struct PowerStreamGeometryTests {
    static func main() {
        var count=0
        func check(_ value:Bool,_ name:String) { precondition(value,name);count += 1 }
        let split=PowerStreamGeometry(left:20,right:220,top:20,bottom:170,ports:[StreamPort(top:4,bottom:54),StreamPort(top:86,bottom:186)])
        check(split.path.contains(CGPoint(x:35,y:70)),"Shared trunk stays filled across the split")
        check(!split.path.contains(CGPoint(x:200,y:70)),"Fork opens into an actual empty gap")
        check(split.path.contains(CGPoint(x:200,y:30)),"Top stream remains filled")
        check(split.path.contains(CGPoint(x:200,y:140)),"Bottom stream remains filled")
        check(split.path.boundingBoxOfPath.minX == 20 && split.path.boundingBoxOfPath.maxX == 220,"Outline stays inside horizontal endpoints")
        check(PowerStreamGeometry(left:0,right:0,top:0,bottom:20,ports:[]).path.isEmpty,"Empty layout draws no invalid path")
        for index in split.ports.indices {
            for fraction:CGFloat in [0.4,0.5,0.6] {
                check(split.path.contains(CGPoint(x:split.left+(split.right-split.left)*fraction,y:split.center(of:index,at:fraction))),"Labels follow the filled center of curved branches")
            }
        }
        let merge=PowerStreamGeometry(left:20,right:220,top:20,bottom:170,ports:split.ports,reversed:true)
        check(merge.path.contains(CGPoint(x:205,y:70)),"Input merge shares the destination trunk")
        check(!merge.path.contains(CGPoint(x:40,y:70)),"Input streams remain separated before merging")
        var shape=PowerStreamShape(geometry:split)
        var next=split;next.left=40;next.right=260;next.top=30;next.ports[0].bottom=60
        shape.animatableData=PowerStreamShape(geometry:next).animatableData
        check(shape.geometry == next,"Source, destination and port geometry all interpolate")
        var delta=StreamVector(values:[2,4,6]);delta.scale(by:0.5)
        check(delta == StreamVector(values:[1,2,3]),"Interpolation scales all edges")
        check(StreamVector.zero+delta == delta,"Animation zero preserves geometry")
        print("PASS: \(count) connected power-stream geometry checks")
    }
}
