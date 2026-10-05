begin;
insert into iran_calendar_event(jalali_year,jalali_month,jalali_day,title_fa,is_official_holiday,source_name,source_url) values
(1405,1,1,'عید سعید فطر و آغاز نوروز',true,'تقویم رسمی کشور ۱۴۰۵','https://calendar.ut.ac.ir/'),
(1405,1,2,'تعطیل عید سعید فطر و عید نوروز',true,'تقویم رسمی کشور ۱۴۰۵','https://calendar.ut.ac.ir/'),
(1405,1,25,'شهادت امام جعفر صادق (ع)',true,'تقویم رسمی کشور ۱۴۰۵','https://calendar.ut.ac.ir/'),
(1405,3,6,'عید سعید قربان',true,'تقویم رسمی کشور ۱۴۰۵','https://calendar.ut.ac.ir/'),
(1405,3,14,'عید سعید غدیر خم و رحلت امام خمینی',true,'تقویم رسمی کشور ۱۴۰۵','https://calendar.ut.ac.ir/'),
(1405,4,3,'تاسوعای حسینی',true,'تقویم رسمی کشور ۱۴۰۵','https://calendar.ut.ac.ir/'),
(1405,4,4,'عاشورای حسینی',true,'تقویم رسمی کشور ۱۴۰۵','https://calendar.ut.ac.ir/'),
(1405,5,13,'اربعین حسینی',true,'تقویم رسمی کشور ۱۴۰۵','https://calendar.ut.ac.ir/'),
(1405,5,21,'رحلت حضرت رسول اکرم (ص) و شهادت امام حسن مجتبی (ع)',true,'تقویم رسمی کشور ۱۴۰۵','https://calendar.ut.ac.ir/'),
(1405,5,22,'شهادت امام رضا (ع)',true,'تقویم رسمی کشور ۱۴۰۵','https://calendar.ut.ac.ir/'),
(1405,5,30,'شهادت امام حسن عسکری (ع)',true,'تقویم رسمی کشور ۱۴۰۵','https://calendar.ut.ac.ir/'),
(1405,6,8,'ولادت حضرت رسول اکرم (ص) و امام جعفر صادق (ع)',true,'تقویم رسمی کشور ۱۴۰۵','https://calendar.ut.ac.ir/'),
(1405,8,22,'شهادت حضرت فاطمه زهرا (س)',true,'تقویم رسمی کشور ۱۴۰۵','https://calendar.ut.ac.ir/'),
(1405,10,2,'ولادت امام علی (ع) و روز پدر',true,'تقویم رسمی کشور ۱۴۰۵','https://calendar.ut.ac.ir/'),
(1405,10,16,'مبعث حضرت رسول اکرم (ص)',true,'تقویم رسمی کشور ۱۴۰۵','https://calendar.ut.ac.ir/'),
(1405,11,4,'ولادت حضرت قائم (عج) و نیمه شعبان',true,'تقویم رسمی کشور ۱۴۰۵','https://calendar.ut.ac.ir/'),
(1405,12,9,'شهادت حضرت علی (ع)',true,'تقویم رسمی کشور ۱۴۰۵','https://calendar.ut.ac.ir/'),
(1405,12,19,'عید سعید فطر',true,'تقویم رسمی کشور ۱۴۰۵','https://calendar.ut.ac.ir/'),
(1405,12,20,'تعطیل به مناسبت عید سعید فطر',true,'تقویم رسمی کشور ۱۴۰۵','https://calendar.ut.ac.ir/')
on conflict do nothing;
commit;
