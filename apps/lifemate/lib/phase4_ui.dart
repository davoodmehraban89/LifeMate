import 'package:flutter/material.dart';

class Phase4Hub extends StatelessWidget {
  const Phase4Hub({super.key});
  @override Widget build(BuildContext context)=>Scaffold(appBar:AppBar(title:const Text('راهنمای هوشمند')),body:ListView(padding:const EdgeInsets.all(20),children:[
    const Text('یادگیری و حال خوب',style:TextStyle(fontSize:28,fontWeight:FontWeight.w700)),const SizedBox(height:8),
    const Text('راهنماها پیشنهاد می‌دهند؛ تصمیم و اجرای تغییرها با خودت است.'),const SizedBox(height:20),
    _card(context,Icons.school_rounded,'راهنمای مطالعه','هدف مطالعه، مرور فعال و برنامه‌های کوتاه و قابل انجام.'),
    _card(context,Icons.auto_awesome_rounded,'راهنمای برنامه‌ریزی','سه اولویت، شکستن کارها و پیشنهاد برنامه بدون تغییر خودکار.'),
    _card(context,Icons.self_improvement_rounded,'حال خوب','ثبت خصوصی حال، انرژی و استرس و پیشنهادهای حمایتی؛ نه تشخیص پزشکی.'),
    const Card(child:Padding(padding:EdgeInsets.all(16),child:Text('حریم خصوصی: گفت‌وگوهای راهنما و یادداشت‌های حال خوب خصوصی‌اند. عضویت خانواده به‌تنهایی دسترسی به متن آن‌ها ایجاد نمی‌کند.'))),
  ]));
  Widget _card(BuildContext c,IconData icon,String title,String subtitle)=>Card(child:ListTile(leading:Icon(icon),title:Text(title),subtitle:Text(subtitle),trailing:const Icon(Icons.chevron_left_rounded)));
}
