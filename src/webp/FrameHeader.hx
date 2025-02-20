package webp;

typedef FrameHeader = {
    keyFrame:Bool,
    versionNumber:Int,
    showFrame:Bool,
    firstPartitionLen:Int,
    width:Int,
    height:Int,
    xScale:Int,
    yScale:Int,
}