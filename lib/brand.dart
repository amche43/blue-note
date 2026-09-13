import 'package:flutter/material.dart';

/// Display exact source pixels through a crop window; keep supplied sheets intact.
class BrandCrop extends StatelessWidget {
  final String sheet;
  final Rect region;
  final double width;
  final double sourceWidth,sourceHeight;
  const BrandCrop({super.key,required this.sheet,required this.region,this.width=64,this.sourceWidth=1448,this.sourceHeight=1086});
  @override Widget build(BuildContext context){
    final scale=width/region.width;
    return SizedBox(width:width,height:region.height*scale,child:ClipRect(child:Stack(children:[
      Positioned(left:-region.left*scale,top:-region.top*scale,width:sourceWidth*scale,height:sourceHeight*scale,
        child:Image.asset('assets/brand/$sheet.png',fit:BoxFit.fill,excludeFromSemantics:true)),
    ])));
  }
}
class BlueMascot extends StatelessWidget {
  final double width;
  const BlueMascot({super.key,this.width=100});
  @override Widget build(BuildContext context)=>BrandCrop(sheet:'mascots',region:const Rect.fromLTWH(565,129,240,304),width:width);
}
class BlueAvatar extends StatelessWidget {
  final int index;
  final double width;
  const BlueAvatar({super.key,this.index=0,this.width=42});
  @override Widget build(BuildContext context)=>SizedBox.square(dimension:width,child:ClipOval(child:FittedBox(fit:BoxFit.cover,child:BrandCrop(sheet:'avatars',region:Rect.fromLTWH(33+(index%8)*174,312,162,191),width:width))));
}
class SubjectArt extends StatelessWidget {
  final String subject;
  const SubjectArt(this.subject,{super.key});
  @override Widget build(BuildContext context){
    final region=<String,Rect>{
      '高等数学':const Rect.fromLTWH(243,390,120,117),'线性代数':const Rect.fromLTWH(378,390,120,117),
      '概率论':const Rect.fromLTWH(514,390,120,117),'数据结构':const Rect.fromLTWH(61,610,144,122),
      '计算机网络':const Rect.fromLTWH(237,610,144,122),'计算机组成原理':const Rect.fromLTWH(412,610,144,122),
      '操作系统':const Rect.fromLTWH(586,610,144,122),'英语':const Rect.fromLTWH(62,837,143,125),
    }[subject]??const Rect.fromLTWH(61,390,132,117);
    return BrandCrop(sheet:'subjects',region:region,width:40);
  }
}
const stickerNames=['开心','点赞','加油','疑问','思考','惊讶','委屈','无语','睡觉','庆祝'];
class BlueSticker extends StatelessWidget {
  final int index;
  final double width;
  const BlueSticker(this.index,{super.key,this.width=72});
  @override Widget build(BuildContext context)=>BrandCrop(sheet:'stickers',region:Rect.fromLTWH(31+index*137,365,130,126),width:width);
}
