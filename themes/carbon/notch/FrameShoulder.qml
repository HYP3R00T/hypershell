import QtQuick

Canvas {
    required property color paintColor
    property bool mirrored: false
    property bool inverted: false
    width: 8
    height: width
    onPaintColorChanged: requestPaint()
    onWidthChanged: requestPaint()
    onHeightChanged: requestPaint()
    onMirroredChanged: requestPaint()
    onInvertedChanged: requestPaint()
    onPaint: {
        const ctx = getContext("2d");
        ctx.reset();
        ctx.clearRect(0, 0, width, height);
        ctx.translate(mirrored ? width : 0, inverted ? height : 0);
        ctx.scale(mirrored ? -1 : 1, inverted ? -1 : 1);
        ctx.beginPath();
        ctx.moveTo(0, 0);
        ctx.arcTo(width, 0, width, height, width);
        ctx.lineTo(width, 0);
        ctx.closePath();
        ctx.fillStyle = paintColor;
        ctx.fill();
    }
}
