/* Design-only, fictional fixtures. No forms, transport, storage or credentials. */
(() => {
  'use strict';
  const fa = n => String(n).replace(/\d/g, x => '۰۱۲۳۴۵۶۷۸۹'[x]);
  const esc = value => String(value).replace(/[&<>"']/g, x => ({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[x]));
  const iconPaths = {
    home:'M3 11 12 3l9 8v10h-6v-7H9v7H3z', plan:'M4 5h16v16H4zM8 3v5m8-5v5M4 11h16m-12 4h2m4 0h2',
    book:'M12 7v14M3 4c4-1 6 0 9 3 3-3 5-4 9-3v14c-4-1-6 0-9 3-3-3-5-4-9-3z',
    focus:'M9 2h6m-3 0v4m7 1 2-2M12 6a8 8 0 1 0 0 16 8 8 0 0 0 0-16m0 4v5l3 2',
    family:'M8 3a3 3 0 1 0 0 6 3 3 0 0 0 0-6m10 4a2 2 0 1 0 0 4 2 2 0 0 0 0-4M2 21v-5c0-5 12-5 12 0v5m3-7c4 0 5 2 5 5v2',
    bell:'M6 9a6 6 0 0 1 12 0c0 7 3 7 3 9H3c0-2 3-2 3-9m4 12h4',
    report:'M4 3v18h18M8 16v-4m5 4V7m5 9v-5',back:'m9 5 7 7-7 7',
    more:'M5 12h.1M12 12h.1M19 12h.1', check:'m4 12 5 5L20 6',
    shield:'m12 2 9 4v6c0 5-9 10-9 10S3 17 3 12V6zm-4 10 3 3 5-6',
    arrow:'M4 12h15m-6-6 6 6-6 6',spark:'m12 2 2 7 7 3-7 2-2 8-2-8-8-2 8-3z',
    empty:'M4 6h16v15H4zM8 3h8v6H8m1 6h6',play:'m8 4 12 8-12 8z',pause:'M8 5v14m8-14v14'
  };
  const icon = (name,size=24) => `<svg width="${size}" height="${size}" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="${iconPaths[name] || iconPaths.spark}"/></svg>`;
  const math = (value,large=false) => `<bdi class="math${large?' large':''}" dir="ltr" data-math="${esc(value)}">${esc(value)}</bdi>`;
  const btn = (label,action,kind='',attrs='') => `<button class="btn ${kind}" data-action="${action}" ${attrs}>${label}</button>`;
  const route = (label,id,kind='secondary',attrs='') => btn(label,`go:${id}`,kind,attrs);
  const card = (title,body,extra='') => `<section class="card ${extra}"><h2>${title}</h2>${body}</section>`;
  const helper = text => `<p class="helper">${text}</p>`;
  const notice = text => `<div class="banner"><strong>${icon('shield',18)} فقط پیش‌نمایش</strong><p>${text}</p></div>`;
  const readonly = (label,value,id='') => `<label class="field">${label}<input ${id?`id="${id}"`:''} type="text" readonly value="${esc(value)}" autocomplete="off" aria-description="مقدار ساختگی و فقط خواندنی"/></label>`;
  const axis = () => `<figure class="number-line" dir="ltr" aria-label="محور متناسب: منفی ده، منفی سه، صفر، سه"><svg class="axis-svg" viewBox="0 0 300 160" role="img" aria-label="فاصله‌های روی محور متناسب‌اند"><path d="M0 80H300M2 70V90M161.54 70V90M230.77 70V90M298 70V90" stroke="currentColor" stroke-width="2" fill="none"/><text x="2" y="40" text-anchor="start" direction="ltr">−۱۰</text><text x="161.54" y="40" text-anchor="middle" direction="ltr">−۳</text><text x="230.77" y="140" text-anchor="middle" direction="ltr">۰</text><text x="298" y="40" text-anchor="end" direction="ltr">۳</text></svg></figure>`;
  const shared = ['تکلیف‌های به اشتراک گذاشته‌شده','خلاصهٔ زمان ثبت‌شدهٔ مجاز','پیشرفت آموزشیِ قابل اشتراک'];
  const privacy = () => `<ul class="privacy-list">${shared.map(text=>`<li>${icon('check',18)} ${text}</li>`).join('')}</ul><div class="banner"><strong>چه چیزهایی در این خلاصه نیست؟</strong><p>یادداشت خصوصی، گفت‌وگو و اطلاعات سلامت در این خلاصه قرار نمی‌گیرند.</p></div>`;
  const systemStates = ['normal','empty','loading','error','offline','conflict','session','rate-limit'];
  const definitions = [
    ['welcome','خوش‌آمد و انتخاب نقش','student'],['parent-phone','ورود نمایشی والد','parent'],['otp','کد یکبارمصرف نمونه','parent'],
    ['create-child','پروفایل ساختگی کودک','parent'],['consent','متن رضایت نمایشی','parent'],['invite-card','دعوت نمونهٔ کودک','parent'],
    ['child-invite','ورود نمایشی دانش‌آموز','student'],['child-visibility','والدم چه چیزی می‌بیند؟','student'],
    ['home','امروزِ من','student',true],['plan','برنامهٔ من','student',true],['task','جزئیات کار','student'],['edit-task','زمان کار نمونه','student'],
    ['courses','درس‌های من','student',true],['lesson','عددهای صحیح','student',true],['practice','تمرین راهنما','student'],
    ['quiz','آزمونک نمونه','student',true],['quiz-result','نتیجهٔ همین پیش‌نمایش','student'],['quiz-review','مرور پاسخ‌ها','student'],
    ['focus','وقت تمرکز','student',true],['family','خانواده و اشتراک','student',true],['reminders','یادآوری‌ها','student',true],['settings','حساب و تنظیمات','student',true],['student-report','گزارش من','student',true],
    ['parent-home','خانهٔ والد','parent',true],['report','گزارش‌های مجاز','parent',true],['parent-plan','برنامهٔ شخصی والد','parent',true],
    ['parent-family','خانوادهٔ نمونه','parent',true],['parent-settings','تنظیمات والد','parent',true],['parent-content','مرور وضعیت محتوای نمایشی','parent'],
    ['parent-reminders','یادآوری‌های خود والد','parent',true],['parent-account-actions','مدیریت حساب والدِ نمونه','parent'],
    ['parent-leave-family','خروج والد از خانواده','parent'],['parent-export-data','خروجی دادهٔ خود والد','parent'],['parent-delete-account','حذف حساب والد','parent'],
    ['parent-confirm-action','تأیید دومِ والد','parent'],['parent-action-preview','پایان مسیر نمونهٔ والد','parent'],
    ['account-actions','مدیریت حساب نمونه','student'],['leave-family','خروج از خانواده','student'],['export-data','خروجی داده','student'],
    ['delete-account','حذف حساب','student'],['confirm-action','تأیید دومِ نمایشی','student'],['action-preview','پایان شبیه‌سازی','student'],
    ['math-bidi','نمونهٔ جهت‌دهی ریاضی','student'],['components','اجزای رابط','student']
  ];
  const screens = definitions.map(([id,title,role,main=false])=>({id,title,role,main,states:main?systemStates:id==='otp'?['normal','wrong','expired','cooldown','rate-limit']:['normal','error']}));
  const lookup = id => screens.find(s=>s.id===id) || screens.find(s=>s.id==='home');
  const initialTasks = () => [
    {title:'مرور عددهای صحیح',subject:'ریاضی',time:'۱۶:۳۰ تا ۱۶:۵۵',status:'planned',shared:true},
    {title:'خواندن یک متن کوتاه',subject:'فارسی',time:'۱۷:۳۰ تا ۱۷:۵۰',status:'planned',shared:true},
    {title:'ورزش سبک',subject:'برنامهٔ شخصی',time:'۱۸:۰۰ تا ۱۸:۲۰',status:'planned',shared:false},
    {title:'آماده‌کردن کیف',subject:'برنامهٔ شخصی',time:'انجام‌شده در امروزِ نمونه',status:'completed',shared:false}
  ];
  const questions = [
    {text:'سه واحد پایین‌تر از صفر کدام است؟',answers:['−۳','۳','۰','−۱۰'],correct:0,why:'سه گام به سمت چپِ صفر، به منفی سه می‌رسد.'},
    {text:'کدام عدد از منفی سه کوچک‌تر است؟',answers:['۰','۲','−۱۰','۳'],correct:2,why:'منفی ده در محور، سمت چپ منفی سه است.'},
    {text:'حاصل این عبارت چیست؟',formula:'۷ + (−۳)',answers:['۱۰','۴','−۴','۳'],correct:1,why:'از هفت، سه گام به چپ می‌رویم و به چهار می‌رسیم.'},
    {text:'دما از منفی سه، پنج درجه بیشتر می‌شود. دمای تازه؟',answers:['−۸','۸','−۲','۲'],correct:3,why:'پنج واحد افزایش از منفی سه، به مثبت دو می‌رسد.'},
    {text:'فاصلهٔ منفی سه تا صفر چند واحد است؟',answers:['−۳','۳','۰','۶'],correct:1,why:'فاصله منفی نیست؛ سه واحد است.'},
    {text:'قرینهٔ منفی ده نسبت به صفر کدام است؟',answers:['۱۰','۰','−۱۰','−۱'],correct:0,why:'قرینه همان فاصله را در سمت دیگر صفر دارد.'},
    {text:'کدام عبارت نتیجهٔ صفر دارد؟',answers:['۳ + ۳','−۳ + (−۳)','−۳ + ۳','۳ + ۰'],correct:2,why:'سه واحد منفی و سه واحد مثبت همدیگر را خنثی می‌کنند.'},
    {text:'از منفی ده، هفت گام به راست برو. به کجا می‌رسی؟',answers:['−۱۷','۱۷','۳','−۳'],correct:3,why:'منفی ده به‌علاوهٔ هفت برابر منفی سه است.'},
    {text:'کدام عدد صحیح بین منفی سه و منفی یک است؟',answers:['−۲','۰','۲','−۴'],correct:0,why:'ترتیب این بخش محور: منفی سه، منفی دو، منفی یک است.'},
    {text:'منفی سه را با منفی سه جمع کن.',answers:['۰','۶','−۶','−۳'],correct:2,why:'دو حرکت سه‌واحدی به چپ، شش واحد حرکت به چپ است.'}
  ];
  let screen='home', state='normal', theme='calm', selectedRole=null, selectedTask=0, history=[];
  let tasks=initialTasks(), answers=Array(10).fill(null), question=0, practiceAnswer=null, practiceChecked=false;
  let consentChecked=false, actionChecked=false, pendingAction='delete', timerRunning=false, timerSeconds=1500, timerRest=false, toast='';
  let remindOptions=[true,true,false], reviewExpanded=false, planRange='day', planDay=0;
  const currentRole = () => lookup(screen).role;
  const styles = name => Object.entries(window.DESIGN_TOKENS.colors[name] || window.DESIGN_TOKENS.colors.calm).map(([key,value])=>`--${key.replace(/[A-Z]/g,x=>'-'+x.toLowerCase())}:${value}`).join(';');
  const displayStatus = value => value==='completed'?'انجام‌شده':value==='started'?'شروع‌شده':'برنامه‌ریزی‌شده';
  function taskRows(forBoard=false,parent=false) {
    const rows=parent?tasks.filter(t=>t.shared):tasks;
    return rows.map((task,i)=>`<article class="card task" data-qa="today-task"><span class="complete-icon" aria-hidden="true">${task.status==='completed'?icon('check',18):icon('plan',16)}</span><div class="task-copy"><h3>${esc(task.title)}</h3>${helper(task.subject+' · '+task.time)}<span class="tag${task.status==='completed'?' success':''}">${displayStatus(task.status)}</span></div>${parent?route('جزئیات مجاز','report','secondary small'):btn(task.status==='completed'?'مرور':'شروع',`start-task:${i}`,'small',`data-qa="task-start"`)}</article>`).join('');
  }
  function visibility() {return `${card('اشتراک روشن، قدم‌به‌قدم',`<p>در این نمونه، سرپرست‌های مجازِ خانواده فقط خلاصهٔ زیر را می‌بینند. عضو خانواده بودن به معنی دیدن همه‌چیز نیست.</p>${privacy()}`)}${card('این کار برای چه کسی دیده شود؟',`<p>اشتراک هر تکلیف جدا انتخاب می‌شود: «فقط من» یا «سرپرستان من»؛ فقط برای همان کار.</p>`)}${route('متوجه شدم؛ خانهٔ نمونه','home','wide')}`;}
  function errorState(id) {
    const copy={welcome:'ابتدا یک نقش نمونه را انتخاب کن.', 'parent-phone':'فقط شمارهٔ پوشانده‌شدهٔ نمونه قابل انتخاب است؛ شمارهٔ واقعی وارد نکن.',
      'create-child':'برای این طرح، مشخصات ساختگی را انتخاب کن؛ نام و پایهٔ نمونه لازم‌اند.', 'child-invite':'کد دعوت یا PIN نمونه درست نیست. دوباره نمونهٔ آماده را انتخاب کن.',
      consent:'برای ادامهٔ نمایشی، متن را بخوان و گزینهٔ فهمیدن آن را انتخاب کن.', 'invite-card':'ساخت کد واقعی در این طرح ممکن نیست؛ فقط کارت نمونه را می‌بینی.',
      'child-visibility':'بارگذاری دیدپذیری شبیه‌سازی نشد. این خطای طراحی است؛ داده‌ای از سرور خوانده نشده.',
      'leave-family':'خروج واقعی وجود ندارد؛ برای بررسی دوباره به مرحلهٔ قبل برگرد.', 'export-data':'فایل دادهٔ واقعی ساخته نمی‌شود؛ فقط ساختار نمونه قابل مشاهده است.', 'delete-account':'هیچ حساب واقعی برای حذف وجود ندارد؛ این فقط مسیر تأیید را نشان می‌دهد.'};
    return `<div class="banner error" data-qa="state-error" role="alert"><strong>خطای نمونه</strong><p>${copy[id] || 'دریافت اطلاعات شبیه‌سازی‌شده ناموفق بود. هیچ عملیات واقعی انجام نشده است.'}</p>${btn('تلاش دوباره','state:normal','secondary')}</div>`;
  }
  function systemContent(id,variant) {
    if(variant==='loading') return `<p class="loading-label" role="status">در حال بارگذاریِ نمایشی…</p><div data-qa="state-loading" aria-busy="true" aria-label="اسکلت بارگذاری"><div class="skeleton short"></div><div class="skeleton tall"></div><div class="skeleton"></div><div class="skeleton tall"></div></div>${helper('هیچ درخواستی ارسال نشده است.')}`;
    if(variant==='empty') return `<div class="empty" data-qa="state-empty">${icon('empty',48)}<h2>${id==='home'?'امروز کاری نداری':id==='courses'?'درسی برای نمایش نیست':id==='report'?'گزارش مجازی برای نمایش نیست':'این فهرست خالی است'}</h2><p>می‌توانی از یک قدم کوچک شروع کنی؛ لازم نیست همهٔ روز را پر کنی.</p>${route(id==='home'?'برنامهٔ نمونه را ببین':'بازگشت به خانه',id==='home'?'plan':lookup(id).role==='parent'?'parent-home':'home','wide')}${btn('بازگرداندن دادهٔ ساختگی','state:normal','secondary wide')}</div>`;
    if(variant==='session') return `<div class="banner error" data-qa="state-session" role="alert"><strong>نشست نمونه پایان یافته</strong><p>این حالت، ورود واقعی نیست. دادهٔ خصوصی یا رمز ورود نمایش داده نمی‌شود.</p>${route('بررسی دوبارهٔ ورود','welcome','wide')}</div>`;
    if(variant==='rate-limit') return `<div class="banner error" data-qa="state-rate-limit" role="alert"><strong>۴۲۹ · تلاش زیاد، بعداً دوباره</strong><p>مهلت نمونه: ۶۰ ثانیه. هیچ درخواست واقعی ارسال نشده است.</p>${btn('تلاش دوباره؛ پس از مهلت','noop','secondary wide','disabled')}${btn('شبیه‌سازی پایان مهلت','state:normal','secondary wide')}</div>`;
    if(variant==='conflict') return `<div class="banner error" data-qa="state-conflict" role="alert"><strong>دو نسخهٔ نمونه با هم فرق دارند</strong><p>قبل از انتخاب، هر دو را ببین. هیچ‌کدام خودکار جای دیگری نمی‌نشیند.</p></div>${card('تغییر روی این دستگاه',`<p>مرور ریاضی: ساعت ۱۷:۰۰ · تغییر ساختگی در صف</p>`)}${card('نسخهٔ دیگرِ ساختگی',`<p>مرور ریاضی: ساعت ۱۶:۳۰ · نسخهٔ نمونهٔ قبلی</p>`)}<div class="stack">${btn('انتخاب نسخهٔ این دستگاه','resolve:local')}${btn('انتخاب نسخهٔ دیگر','resolve:other','secondary')}</div>${helper('انتخاب فقط در حافظهٔ این طرح اعمال می‌شود؛ همگام‌سازی واقعی وجود ندارد.')}`;
    return null;
  }
  function body(id,variant='normal',forBoard=false) {
    const meta=lookup(id);
    if(meta.main && !['normal','offline','error'].includes(variant)) return systemContent(id,variant);
    if(variant==='rate-limit') return systemContent(id,variant);
    if(id.startsWith('parent-') && ['reminders','account-actions','leave-family','export-data','delete-account','confirm-action','action-preview'].includes(id.slice(7))) {
      return body(id.slice(7),variant,forBoard).replaceAll('go:account-actions','go:parent-account-actions').replaceAll('go:action-preview','go:parent-action-preview').replaceAll('go:export-data','go:parent-export-data').replaceAll('go:leave-family','go:parent-leave-family').replaceAll('go:delete-account','go:parent-delete-account');
    }
    let prefix=variant==='error'?errorState(id):'';
    if(variant==='offline') prefix=`<div class="banner" data-qa="state-offline" role="status"><strong>بدون اینترنت · نسخهٔ نمونه زنده نیست</strong><p>نمایش این داده‌ها فقط برای بررسی طراحی است.</p></div>${card('۲ تغییر ساختگی در صف',`<ol class="queue" data-qa="queued-list"><li>تغییر زمان مرور ریاضی</li><li>تیک انجام کار امروز</li></ol>${btn('شبیه‌سازی اتصال دوباره','state:normal','secondary')}`)}`;
    let content='';
    switch(id) {
      case 'welcome': content=`<div class="hero">${icon('spark',40)}<h2>یک قدم روشن برای امروزت.</h2><p>لایف‌گاید، همراه برنامهٔ شخصی و خانوادگی.</p></div>${notice('هیچ ورود، ارسال کد، ذخیره یا اتصال به سرور انجام نمی‌شود. از دادهٔ واقعی استفاده نکن.')}<h2>کدام مسیر را می‌خواهی ببینی؟</h2><div class="choices" role="radiogroup" aria-label="نقش نمونه"><button class="choice" role="radio" aria-checked="${selectedRole==='parent'}" data-action="role:parent">${icon('family')}والد ${selectedRole==='parent'?'✓':''}</button><button class="choice" role="radio" aria-checked="${selectedRole==='student'}" data-action="role:student">${icon('book')}دانش‌آموز ${selectedRole==='student'?'✓':''}</button></div><div class="button-row">${btn('ادامهٔ مسیر نمونه','welcome-next','wide')}</div>`;break;
      case 'parent-phone':content=`<h2>مسیر ورود والد</h2><p>شمارهٔ زیر پوشانده‌شده و ساختگی است؛ قابل ویرایش نیست.</p>${readonly('موبایل ساختگی','09•• ••• ••42')}${helper('شماره یا ایمیل واقعی وارد نکن. این طرح فرم واقعیِ تماس ندارد.')}${btn('دیدن مرحلهٔ کد نمونه','go:otp','wide')}${route('برگشت به انتخاب نقش','welcome','secondary wide')}`;break;
      case 'otp':{
        const messages={wrong:'کد نمونه اشتباه است. دوباره کد آماده را انتخاب کن.',expired:'کد نمونه منقضی شده است. یک نمونهٔ تازه انتخاب کن.',cooldown:'برای ارسال مجددِ نمایشی ۴۵ ثانیه باقی مانده است.'};
        content=`<h2>کد یکبارمصرفِ شبیه‌سازی‌شده</h2><p>هیچ پیامکی ارسال نشده است.</p>${readonly('کد ساختگی','۱۲۳۴۵۶')}<p class="helper">مقصد نمایشی: <bdi dir="ltr">09•• ••• ••42</bdi></p>${messages[variant]?`<div class="banner ${variant==='cooldown'?'':'error'}" role="alert"><strong>${messages[variant]}</strong></div>`:''}${btn('ادامه با کد آماده','go:parent-home','wide')}<div class="button-row">${btn('ارسال مجددِ نمونه',variant==='cooldown'?'noop':'state:cooldown','secondary',variant==='cooldown'?'disabled':'')}${variant==='cooldown'?btn('پایان مهلتِ نمونه','state:normal','secondary'):btn('دیدن خطای کد','state:wrong','secondary')}</div><div class="button-row">${btn('کد منقضیِ نمونه','state:expired','secondary')}${btn('محدودیت تلاشِ نمونه','state:rate-limit','secondary')}</div>${route('ساخت پروفایل نمونهٔ کودک','create-child','secondary wide')}`;break;}
      case 'create-child':content=`<h2>یک پروفایل ساختگی بسازیم</h2><p>فقط ظاهر این مرحله را بررسی کن؛ مشخصات واقعی کودک وارد نکن.</p>${readonly('نام نمایشی نمونه','دانش‌آموز نمونه')}${readonly('پایهٔ تحصیلی نمونه','هفتم')}${readonly('سال تولد نمونه','۱۳۹۲')}${helper('بدون شمارهٔ کودک، بدون ایمیل کودک. این مقادیر هویت یا سن کسی را تأیید نمی‌کنند.')}${btn('بررسی متن رضایتِ نمونه','go:consent','wide')}`;break;
      case 'consent':content=`<span class="tag warning">نسخهٔ متن نمایشی ۰۲</span><h2>پیش از پیوستن، روشن بدانیم</h2><p>این متن، رضایت حقوقی یا سیاست تازه نیست؛ همان مرز نمایش v1 را به زبان ساده توضیح می‌دهد.</p>${card('چه چیزی می‌تواند مشترک باشد؟',privacy())}<label class="check-row"><input type="checkbox" data-action="consent-check" ${consentChecked?'checked':''}/><span>متن نمونه را خواندم؛ می‌دانم در این طرح رضایتی ثبت نمی‌شود.</span></label><div class="button-row">${btn('ادامهٔ نمایشی به دعوت','go:invite-card','wide',consentChecked?'':'disabled')}</div>${helper('نسخه، سن، اعتبار سرپرستی و رضایت واقعی به بررسی و تصویب جدا نیاز دارند.')}`;break;
      case 'invite-card':content=`<h2>کارت دعوتِ ساختگی</h2>${readonly('کد نمایشی','DEMO-C7A2')}${readonly('PIN نمایشی','••••')}${notice('این کد قابل ورود به هیچ سامانه‌ای نیست. QR واقعی، اسکن یا پیوند ورود ساخته نشده است.')}<p>در مسیر دانش‌آموز، پیش از خانه توضیح دید والد نمایش داده می‌شود.</p>${route('دیدن مسیر دستگاه کودک','child-invite','wide')}${route('برگشت به خانوادهٔ والد','parent-family','secondary wide')}`;break;
      case 'child-invite':content=`<h2>با دعوت وارد مسیر نمونه شو</h2><p>هیچ شماره یا ایمیلی لازم نیست. این دو مقدار فقط برای نمایش‌اند.</p>${readonly('کد دعوت نمونه','DEMO-C7A2')}${readonly('PIN نمونه','••••')}${btn('ادامه با دعوت آماده','go:child-visibility','wide')}${btn('دیدن خطای کد یا PIN','state:error','secondary wide')}`;break;
      case 'child-visibility':content=visibility();break;
      case 'home':{
        const done=tasks.filter(t=>t.status==='completed').length;
        content=`<p class="helper">سلام، دانش‌آموز نمونه · امروزِ ساختگی</p><div class="hero"><div class="hero-art">${icon('spark',56)}</div><p class="eyebrow">قدم بعدی</p><h2>یک نوبت کوتاه ریاضی</h2><p>عددهای صحیح را مرور کن؛ بعد یک تمرین کوچک.</p>${btn('شروع قدم بعدی','start-task:0','wide')}</div><section aria-label="پیشرفت امروز"><h2>پیشرفت امروز</h2><p class="progress-label">${fa(done)} از ${fa(tasks.length)} کار نمونه انجام‌شده</p><div class="progress-track" role="progressbar" aria-label="کارهای انجام‌شده" aria-valuemin="0" aria-valuemax="4" aria-valuenow="${done}"><div class="progress-fill" style="width:${done/tasks.length*100}%"></div></div></section><div class="section-title"><h2>کارهای امروز</h2><span class="tag">${fa(tasks.length)} کار نمونه</span></div>${taskRows(forBoard)}`;break;}
      case 'plan':content=`<h2>برنامهٔ امروز و هفته</h2><p class="helper">زمان‌ها ساختگی‌اند؛ انتخاب روز فقط نمایش را عوض می‌کند.</p><div class="choices" role="tablist" aria-label="بازهٔ برنامه"><button role="tab" aria-selected="${planRange==='day'}" class="choice" data-action="plan-range:day">امروز ${planRange==='day'?'✓':''}</button><button role="tab" aria-selected="${planRange==='week'}" class="choice" data-action="plan-range:week">این هفته ${planRange==='week'?'✓':''}</button></div>${planRange==='week'?`<div class="choices" role="tablist" aria-label="روزهای هفته">${['شنبه','یکشنبه','دوشنبه','سه‌شنبه','چهارشنبه','پنجشنبه','جمعه'].map((d,i)=>`<button class="choice" role="tab" aria-selected="${planDay===i}" data-action="plan-day:${i}">${d}${planDay===i?' ✓':''}</button>`).join('')}</div><p class="helper">برنامهٔ ${['شنبه','یکشنبه','دوشنبه','سه‌شنبه','چهارشنبه','پنجشنبه','جمعه'][planDay]} · زمان‌بندی ساختگی</p>`:''}<div class="section-title"><h2>با وقت خودت جلو برو</h2></div>${taskRows(forBoard)}${route('بررسی زمان یک کار','edit-task','wide')}`;break;
      case 'task':{const task=tasks[selectedTask]||tasks[0];content=`<span class="tag">${displayStatus(task.status)}</span><h2>${esc(task.title)}</h2>${card('زمان و اقدام',`<p>${task.time}</p><p>مدت برنامه‌ریزی‌شدهٔ نمونه: ۲۵ دقیقه</p><div class="button-row">${btn('شروع نوبت نمونه','task-focus')}${route('ویرایش زمان نمونه','edit-task')}</div>`)}${card('اشتراک همین کار',`<p>${task.shared?'سرپرستان من':'فقط من'} · فقط برای همین کار</p><p class="helper">اشتراک در این طرح، مجوز سرور یا تغییر سیاست نمی‌سازد.</p>`)}${btn(task.status==='completed'?'برگرداندن تیک در طرح':'انجام شد؛ فقط در طرح','complete-task','wide')}`;break;}
      case 'edit-task':content=`${notice('این صفحه فقط شکل انتخاب زمان را نشان می‌دهد. ذخیرهٔ پایدار ندارد.')}${readonly('عنوان کار نمونه',(tasks[selectedTask]||tasks[0]).title)}${readonly('شروع نمونه','۱۶:۳۰')}${readonly('پایان نمونه','۱۶:۵۵')}<div class="choices">${btn('نمونهٔ ساعت بعدی','sample-time','secondary wide')}</div>${helper('با انتخاب نمونهٔ دیگر، فقط نوشتهٔ همین پیش‌نمایش تغییر می‌کند.')}${route('برگشت به جزئیات','task','wide')}`;break;
      case 'courses':content=`<span class="tag">پایهٔ هفتم · نمونه</span><h2>یک درس، با قدم‌های روشن</h2><p>محتوای این بسته ساختگی است و بازبینی معلم نشده؛ نمایشِ وضعیت منتشرشده در اینجا فقط شبیه‌سازی رابط است.</p>${card('ریاضی · عددهای صحیح',`<p>هدف، توضیح، مثال حل‌شده، تمرین و آزمونک.</p>${route('بازکردن نمونهٔ درس','lesson','wide')}`)}${helper('در فهرست دانش‌آموز، رکوردِ نمایشیِ draft اصلاً رندر نمی‌شود. نشان مدیریتیِ پیش‌نویس یا بازبینی‌شده در این نما وجود ندارد.')}`;break;
      case 'lesson':content=`<p class="helper">ریاضی هفتم · محتوای اصیلِ ساختگی، تأیید آموزشی نشده</p><h2>عددها دو سمتِ صفر دارند</h2><section class="lesson-block"><h3>هدف این قدم</h3><p>عدد منفی را روی محور پیدا کنی و یک جمع ساده با آن انجام بدهی.</p></section><section class="lesson-block"><h3>توضیح کوتاه</h3><p>صفر را یک نقطهٔ مرجع بگیر. سمت راست، عددهای مثبت و سمت چپ، عددهای منفی قرار می‌گیرند.</p></section>${axis()}<section class="lesson-block"><h3>مثال حل‌شده</h3><p>از هفت شروع کن و سه گام به چپ برو:</p><div class="math-line">${math('۷ + (−۳)')} = ${math('۴')}</div><p>به چهار می‌رسی. حالا بدون نگاه‌کردن، دلیل آن را با زبان خودت بگو.</p></section>${route('تمرین یک‌دقیقه‌ای','practice','wide')}${route('شروع آزمونک · ۱۰ سؤال','quiz','secondary wide','data-qa="quiz-start"')}${helper('ویدئو منبع تأییدشده ندارد؛ اسلات ویدئو در نمای درس پنهان است.')}`;break;
      case 'practice':content=`<h2>یک قدم، بدون عجله</h2><p>از منفی سه، دو گام به راست برو. به کجا می‌رسی؟</p><div class="answers">${['−۵','−۱','۱'].map((a,i)=>`<button class="answer" role="radio" aria-checked="${practiceAnswer===i}" data-action="practice:${i}">${math(a)}${practiceAnswer===i?' ✓':''}</button>`).join('')}</div>${btn('بررسی پاسخ نمونه','practice-check','wide',practiceAnswer===null?'disabled':'')}${practiceChecked?`<div class="banner ${practiceAnswer===1?'success':'error'}"><strong>${practiceAnswer===1?'در این نمونه درست انتخاب کردی':'این بار مسیر را دوباره ببین'}</strong><p>دو گام به راست از منفی سه، به منفی یک می‌رسد. اشتباه بخشی از تمرین است.</p></div>`:''}${route('ادامه به آزمونک','quiz','secondary wide','data-qa="quiz-start"')}`;break;
      case 'quiz':{const q=questions[question];content=`<p class="question-count">پرسش ${fa(question+1)} از ۱۰ · پاسخ‌ها موقت‌اند</p><h2>${q.text}</h2>${q.formula?`<div class="math-line">${math(q.formula,true)}</div>`:''}<div class="answers" role="radiogroup" aria-label="گزینه‌های پرسش">${q.answers.map((a,i)=>`<button class="answer" data-qa="quiz-answer" role="radio" aria-checked="${answers[question]===i}" data-action="answer:${i}">${math(a)}${answers[question]===i?' ✓':''}</button>`).join('')}</div>${btn(question===9?'دیدن نمرهٔ همین طرح':'پرسش بعدی','quiz-next','wide',`data-qa="quiz-next" ${answers[question]===null?'disabled':''}`)}${helper('این آزمونک ساختگی است. نمره ذخیره یا برای والد ارسال نمی‌شود.')}`;break;}
      case 'quiz-result':{const score=questions.filter((q,i)=>answers[i]===q.correct).length;content=`<div class="hero"><h2>یک فرصت برای فهمیدنِ بهتر</h2><p class="quiz-score" data-qa="quiz-result">${fa(score)} از ۱۰ پاسخ درست</p><p>این فقط نمرهٔ پاسخ‌های همین پیش‌نمایش است؛ ذخیره نشده است.</p></div>${route('مرور پاسخ‌ها و دلیلشان','quiz-review','wide','data-qa="quiz-review"')}${btn('دوباره امتحان کن','quiz-retry','secondary wide','data-qa="quiz-retry"')}${route('برگشت به درس','lesson','secondary wide')}`;break;}
      case 'quiz-review':content=`<h2>دلیل هر پاسخ را مرور کن</h2>${questions.map((q,i)=>`<section class="review-answer"><h3>${fa(i+1)}. ${q.text}</h3>${q.formula?`<div class="math-line">${math(q.formula)}</div>`:''}<p><span class="tag ${answers[i]===q.correct?'success':'warning'}">${answers[i]===null?'پاسخی انتخاب نشده':answers[i]===q.correct?'پاسخ درست':'نیاز به مرور'}</span></p><p>انتخاب تو: ${answers[i]===null?'پاسخی انتخاب نشده':math(q.answers[answers[i]])}</p><p>پاسخ نمونه: ${math(q.answers[q.correct])}</p><p>${q.why}</p></section>`).join('')}${btn('دوباره امتحان کن','quiz-retry','wide','data-qa="quiz-retry"')}`;break;
      case 'focus':content=`<span class="tag">${timerRest?'استراحت نمونه':'نوبت مطالعهٔ نمونه'} · فقط هنگام بازبودن طرح</span><h2>یک نوبت کوتاه، یک مکث خوب</h2><div class="timer" data-qa="timer">${fa(String(Math.floor(timerSeconds/60)).padStart(2,'0'))}:${fa(String(timerSeconds%60).padStart(2,'0'))}</div><div class="button-row">${btn(timerRunning?'مکث':'شروع نوبت','timer-toggle')}${btn('استراحت ۵ دقیقه‌ای','timer-break','secondary')}</div>${btn('پایان نمونه و برگشت','timer-stop','secondary wide')}<p>زمان تایمر، اثبات مطالعه یا یادگیری نیست.</p>${helper('این نمونه آلارم، اعلان سیستم یا ثبت مطالعهٔ پایدار ندارد؛ خروج از صفحه، تایمر نمایشی را مکث می‌کند.')}`;break;
      case 'family':content=`<h2>خانوادهٔ نمونه</h2>${card('اشتراک را خودت روشن ببین',`<p>دید سرپرست فقط به خلاصهٔ مجاز مربوط است.</p>${route('والدم چه چیزی می‌بیند؟','child-visibility','wide')}`)}${privacy()}${route('مدیریت حساب نمونه','account-actions','secondary wide')}`;break;
      case 'reminders':content=`<h2>یادآوری به انتخاب تو</h2><p>هیچ اجازهٔ اعلان یا دسترسی سیستم درخواست نمی‌شود.</p>${['قبل از شروع برنامه','یادآوری فردا','صدای اعلان'].map((text,i)=>`<div class="card"><h3>${text}</h3><button role="switch" aria-checked="${remindOptions[i]}" data-action="reminder:${i}" class="choice">${remindOptions[i]?'✓ روشن در طرح':'خاموش در طرح'}</button></div>`).join('')}${card('نمونهٔ ظاهر اعلان',`<strong>لایف‌گاید · نمونه</strong><p>۱۰ دقیقه تا برنامهٔ نمونه باقی مانده.</p>${helper('این کارت اعلان دستگاه نیست.')}`)}`;break;
      case 'settings':content=`<h2>همان ساختار، حال‌وهوای خودت</h2><div class="choices"><button class="choice" data-action="theme:calm" aria-pressed="${theme==='calm'}">آرام ${theme==='calm'?'✓':''}</button><button class="choice" data-action="theme:bright" aria-pressed="${theme==='bright'}">کمی پرانرژی‌تر ${theme==='bright'?'✓':''}</button></div><div class="section-title"><h2>دسترسی‌های روشن</h2></div><div class="action-list">${route('گزارش من','student-report')}${route('والدم چه چیزی می‌بیند؟','child-visibility')}${route('یادآوری‌ها','reminders')}${route('حساب، خروجی و حذف','account-actions')}${route('انتخاب مسیر از ابتدا','welcome')}</div>`;break;
      case 'student-report':content=`<div class="banner"><strong>گزارش شخصیِ ساختگی؛ زنده نیست</strong><p>این خلاصه دربارهٔ خود دانش‌آموز نمونه است.</p></div><h2>قدم‌های امروزِ من</h2><div class="metrics"><div class="metric"><strong>${fa(tasks.filter(t=>t.status==='completed').length)} از ${fa(tasks.length)}</strong><span>کار نمونه انجام‌شده</span></div><div class="metric"><strong>۲۵ دقیقه</strong><span>زمان فرضی برای بررسی ظاهر</span></div></div><p>زمان ثبت‌شده، اثبات یادگیری نیست.</p>${route('چه چیزی برای والدم دیده می‌شود؟','child-visibility','secondary wide')}`;break;
      case 'parent-home':content=`<p class="helper">والد نمونه · فضای مستقل والد</p><div class="hero"><h2>همراهی، با مرز روشن</h2><p>فقط خلاصهٔ آموزشیِ مجاز را ببین؛ بدون ورود به فضای درس یا تمرکز فرزند.</p></div>${card('دانش‌آموز نمونه · پایهٔ هفتم',`<p>۳ کار مجاز از ۵ کار نمونه انجام‌شده</p><p>۴۵ دقیقه زمان ثبت‌شدهٔ نمونه</p>${route('دیدن خلاصهٔ مجاز','report','wide')}`)}${route('ساخت پروفایل ساختگی کودک','create-child','secondary wide')}${helper('یادداشت خصوصی، گفت‌وگو و اطلاعات سلامت در این خلاصه قرار نمی‌گیرند.')}`;break;
      case 'report':content=`<div class="banner"><strong>خلاصهٔ ساختگی؛ دادهٔ زنده نیست</strong><p>آخرین دریافت: زمان فرضیِ این طرح</p></div><h2>گزارش مجازِ دانش‌آموز نمونه</h2><div class="metrics"><div class="metric"><strong>۳ از ۵</strong><span>کار مشترک تکمیل‌شده</span></div><div class="metric"><strong>۴۵ دقیقه</strong><span>زمان ثبت‌شدهٔ مجاز</span></div></div><div class="card"><div class="line-item"><strong>زمان برنامه‌ریزی‌شده</strong><span>۷۵ دقیقه</span></div><div class="line-item"><strong>تکمیل برنامهٔ مجاز</strong><span>۶۰٪</span></div></div>${card('به تفکیک درس',`<div class="line-item"><strong>ریاضی</strong><span>۲ تکلیف · ۲۵ دقیقه</span></div><div class="line-item"><strong>فارسی</strong><span>۱ تکلیف · ۲۰ دقیقه</span></div>`)}<p>زمان ثبت‌شده دربارهٔ کیفیت یادگیری یا سلامت کودک قضاوت نمی‌کند.</p>${helper('نمرهٔ خصوصی آزمونک، متن یادداشت، گفت‌وگو و سلامت نمایش داده نمی‌شوند.')}`;break;
      case 'parent-plan':content=`<h2>برنامهٔ شخصیِ خود والد</h2>${card('هماهنگی برنامهٔ خانواده',`<p>۱۸:۳۰ · زمان فرضی</p><span class="tag">برنامهٔ نمونه</span>`)}${helper('این صفحه برنامهٔ کودک نیست و اختیار ورود به حساب او نمی‌دهد.')}`;break;
      case 'parent-family':content=`<h2>اعضای ساختگی خانواده</h2>${card('دانش‌آموز نمونه',`<p>پایهٔ هفتم · پروفایل نمونه</p>${route('خلاصهٔ آموزشی مجاز','report','wide')}`)}${route('پروفایل ساختگی کودک تازه','create-child','secondary wide')}${route('کارت دعوت نمونه','invite-card','secondary wide')}${helper('مدیریت خانواده، مجوز دیدن همهٔ اطلاعات خصوصی نیست.')}`;break;
      case 'parent-settings':content=`<h2>تنظیمات خود والد</h2><div class="action-list">${route('مرز نمایش و متن نمونه','consent')}${route('وضعیت محتوای نمایشی','parent-content')}${route('مدیریت حساب نمونه','parent-account-actions')}${route('برگشت به انتخاب نقش','welcome')}</div>`;break;
      case 'parent-content':content=`<h2>وضعیت‌ها، فقط برای بررسی رابط</h2>${notice('هیچ درس واقعی در این بسته تأیید نشده است. برچسب‌ها وضعیت نمایشی‌اند؛ نقش مدیریتی واقعی وجود ندارد.')}<article class="card" data-review-status="reviewed"><span class="tag success">بازبینی‌شده · وضعیت نمایشی</span><h3>عددهای صحیح · نسخهٔ ساختگی</h3><p>این نمونه در فهرست کودک قابل نمایش است؛ تأیید معلم نشده.</p></article><article class="card" data-review-status="draft"><span class="tag warning">پیش‌نویس · وضعیت نمایشی</span><h3>نسخهٔ جایگزینِ همین نمونه</h3><p>در فهرست دانش‌آموز پنهان است؛ درس دوم تولید نشده.</p></article>`;break;
      case 'account-actions':content=`<h2>اول بررسی کن، بعد انتخاب</h2><div class="action-list">${route('خروج از خانواده','leave-family')}${route('خروجی گرفتن از داده','export-data')}${route('حذف حساب','delete-account')}</div>${notice('همهٔ مسیرها نمایشی‌اند. فایل دادهٔ واقعی، تغییر عضویت یا حذف حساب انجام نمی‌شود.')}`;break;
      case 'leave-family':content=`<h2>خروج از خانوادهٔ نمونه</h2><p>در این طرح، فقط پیامدها و تأیید دوم را بررسی می‌کنی؛ عضویت واقعی عوض نمی‌شود.</p>${card('پیش از ادامه',`<p>بدان در نسخهٔ واقعی چه اشتراک‌هایی باید قطع شوند و چه داده‌هایی باید قابل بازیابی بمانند. این طرح، سیاست تازه‌ای دربارهٔ آنها تصویب نمی‌کند.</p>`)}${btn('مرحلهٔ دومِ خروج نمونه','confirm:leave','wide')}${route('انصراف و برگشت','account-actions','secondary wide')}`;break;
      case 'export-data':content=`<h2>خروجی گرفتن از دادهٔ خودت</h2><p>پیش از ساخت فایل واقعی، دامنه و حریم خصوصی باید مشخص باشد. اینجا هیچ فایل دادهٔ شخصی ساخته نمی‌شود.</p>${card('ساختار فرضی فایل',`<p>پروفایل نمونه، برنامه‌های خود فرد و راهنمای خواندن فایل.</p>${helper('بدون دادهٔ اعضای دیگر؛ بدون اضافه‌شدن اطلاعات خصوصی به گزارش والد.')}`)}${btn('مرحلهٔ دومِ خروجی نمونه','confirm:export','wide')}${route('انصراف و برگشت','account-actions','secondary wide')}`;break;
      case 'delete-account':content=`<h2>حذف حساب نمونه</h2><div class="banner error"><strong>عملیات حساس در محصول واقعی</strong><p>در اینجا هیچ حسابی حذف نمی‌شود. زمان نگهداری، بازیابی و دامنهٔ حذف، تصمیم سیاستی جداست.</p></div>${route('ابتدا مسیر خروجی را ببین','export-data','secondary wide')}${btn('مرحلهٔ دومِ حذف نمونه','confirm:delete','danger wide')}${route('انصراف و برگشت','account-actions','secondary wide')}`;break;
      case 'confirm-action':content=`<h2>تأیید دوم · ${pendingAction==='leave'?'خروج از خانواده':pendingAction==='export'?'خروجی داده':'حذف حساب'}</h2><p>فقط پایان مسیر طراحی را خواهی دید. هیچ عملیات واقعی انجام نمی‌شود.</p><label class="check-row"><input type="checkbox" data-action="action-check" ${actionChecked?'checked':''}/><span>متوجه‌ام که این فقط شبیه‌سازی است.</span></label><div class="stack">${btn('دیدن پایان مسیر نمونه','go:action-preview','danger wide',actionChecked?'':'disabled')}${route('انصراف','account-actions','secondary wide')}</div>`;break;
      case 'action-preview':content=`<div class="hero"><h2>پایان مسیرِ طراحی</h2><p>فقط این صفحه تغییر کرد. هیچ حساب، عضویت یا فایل واقعی ساخته، ارسال یا حذف نشد.</p></div>${route('برگشت به مدیریت حساب','account-actions','wide')}`;break;
      case 'math-bidi':content=`<h2>ریاضی در جزیرهٔ چپ‌به‌راست</h2><p>متن فارسی در راست‌به‌چپ می‌ماند؛ ترتیب علامت‌ها داخل هر عبارت مستقل است.</p><div data-qa="math-demonstration">${['−۳','−۱۰','۷ + (−۳)','½'].map(value=>`<div class="math-demo-item"><span class="helper">عبارت نمونه</span><div class="math-line">${math(value,true)}</div></div>`).join('')}${axis()}</div>`;break;
      case 'components':content=`<h2>اجزای تکرارشونده</h2>${card('دکمه و وضعیت',`<div class="stack">${btn('دکمهٔ اصلیِ نمونه','toast:فقط کلیک نمونه')}${btn('دکمهٔ غیرفعال','noop','secondary','disabled')}${btn('بارگذاریِ نمونه…','noop','secondary','disabled')}</div>`)}${card('چیپ وضعیت',`<div class="row"><span class="tag success">✓ انجام‌شده</span><span class="tag warning">! در صف</span><span class="tag error">× خطا</span></div>`)}${readonly('ورودی فقط خواندنی','مقدار ساختگی')}${errorState('components')}${route('گفت‌وگوی تأیید نمونه','confirm-action','secondary wide')}`;break;
      default:content='<h2>صفحهٔ نمونه</h2>';
    }
    return prefix+(id==='quiz-review'?`<div data-qa="answer-review">${content}</div>`:content);
  }
  const childNav=[['home','home','خانه'],['plan','plan','برنامه'],['courses','book','درس‌ها'],['focus','focus','تمرکز'],['family','family','خانواده']];
  const parentNav=[['parent-home','home','خانه'],['parent-plan','plan','برنامه'],['parent-family','family','خانواده'],['report','report','گزارش‌ها'],['parent-settings','more','بیشتر']];
  function phone(id,variant='normal',palette='calm',forBoard=false) {
    const meta=lookup(id), parent=meta.role==='parent';
    const active=['task','edit-task'].includes(id)?'plan':['lesson','practice','quiz','quiz-result','quiz-review'].includes(id)?'courses':id;
    const top=parent?'parent-home':'home';
    const actions=meta.main && !['loading','session'].includes(variant)?`${btn(icon('bell'),parent?'go:parent-reminders':'go:reminders','icon-button','aria-label="یادآوری‌ها"')}${btn(icon('report'),parent?'go:report':'go:student-report','icon-button',`aria-label="${parent?'گزارش مجاز':'گزارش من'}"`)}`:'';
    return `<section class="phone" style="${styles(palette)}" data-screen="${id}" data-state="${variant}" data-role="${meta.role}" data-theme="${palette}" aria-label="${meta.title}"><div class="prototype-label">طرح تعاملی با داده ساختگی</div><header class="screen-header">${id==='home'||id==='parent-home'?btn(icon('shield'),parent?'go:parent-settings':'go:settings','icon-button','aria-label="حساب و تنظیمات"'):btn(icon('back'),'back','icon-button','aria-label="برگشت"')}<h1>${meta.title}</h1><div class="header-actions">${actions}</div></header><main class="screen-content">${!forBoard&&toast?`<p class="toast" role="status">${esc(toast)}</p>`:''}${body(id,variant,forBoard)}</main>${meta.main||['task','lesson','practice','quiz-result','quiz-review'].includes(id)?`<nav class="bottom-nav" aria-label="مقصدهای اصلی ${parent?'والد':'دانش‌آموز'}">${(parent?parentNav:childNav).map(([target,image,label])=>`<button data-action="go:${target}" ${active===target?'aria-current="page"':''}>${icon(image,22)}<span>${label}</span></button>`).join('')}</nav>`:`<footer class="screen-footer">نمونهٔ رابط؛ ورود و عملیات واقعی ندارد.</footer>`}</section>`;
  }
  const boardFrames=[
    ...screens.map(s=>({id:s.id,screen:s.id,state:'normal',theme:'calm',title:s.title})),
    ...['welcome','parent-phone','otp','create-child','child-invite','consent','child-visibility','leave-family','export-data','delete-account'].map(id=>({id:id+'-error',screen:id,state:id==='otp'?'wrong':'error',theme:'calm',title:lookup(id).title+' · خطا'})),
    ...['expired','cooldown','rate-limit'].map(variant=>({id:'otp-'+variant,screen:'otp',state:variant,theme:'calm',title:'کد نمونه · '+variant})),
    ...systemStates.filter(s=>s!=='normal').map(variant=>({id:'home-'+variant,screen:'home',state:variant,theme:'calm',title:'خانه · '+variant})),
    ...['home','lesson','plan'].map(id=>({id:'bright-'+id,screen:id,state:'normal',theme:'bright',title:lookup(id).title+' · کمی پرانرژی‌تر'}))
  ];
  function controls() {return `<div class="review-toolbar"><div class="review-brand">LifeGuide / طرح ۰۲</div>${btn(reviewExpanded?'بستن ابزار بررسی':'ابزار بررسی','review-toggle','secondary',`aria-expanded="${reviewExpanded}"`)}${reviewExpanded?`<div class="review-controls"><label>صفحهٔ طرح<select data-control="screen" aria-label="صفحهٔ طرح">${screens.map(s=>`<option value="${s.id}" ${s.id===screen?'selected':''}>${s.title}</option>`).join('')}</select></label><label>حالت نمونه<select data-control="state" aria-label="حالت نمونه">${lookup(screen).states.map(v=>`<option value="${v}" ${v===state?'selected':''}>${({normal:'عادی',empty:'خالی',loading:'بارگذاری',error:'خطا',offline:'بدون اینترنت',conflict:'تعارض',session:'پایان نشست','rate-limit':'محدودیت ۴۲۹',wrong:'کد اشتباه',expired:'کد منقضی',cooldown:'مهلت ارسال مجدد'})[v]}</option>`).join('')}</select></label><label>جهت بصری<select data-control="theme" aria-label="جهت بصری"><option value="calm" ${theme==='calm'?'selected':''}>آرام</option><option value="bright" ${theme==='bright'?'selected':''}>کمی پرانرژی‌تر</option></select></label>${btn('برد کامل صفحه‌ها','board')}</div>`:''}</div><p class="review-note">همهٔ اطلاعات ساختگی است؛ هیچ اتصال، ارسال یا ذخیره‌ای انجام نمی‌شود. محتوای آموزشی تأیید نشده است.</p>`;}
  function render() {
    const query=new URL(location.href).searchParams;
    if(query.get('board')==='1') {
      const requested=query.get('frame'), direction=query.get('direction');
      const frames=requested?boardFrames.filter(f=>f.id===requested):direction?['home','lesson','plan'].map(id=>({id:direction+'-'+id,screen:id,state:'normal',theme:direction,title:lookup(id).title})):boardFrames;
      document.getElementById('app').innerHTML=`<div class="board-mode"><header class="board-heading"><h1>LifeGuide · برد تجربهٔ موبایل v2</h1><p>ساختار یکسان، خوانایی بیشتر، اقدام روشن؛ همهٔ اطلاعات ساختگی و محتوای درسی تأییدنشده.</p>${requested?'':btn('بازگشت به پیش‌نمایش','preview')}</header><div class="board-grid">${frames.map((f,i)=>`<article class="board-panel" data-frame="${f.id}"><div class="panel-caption"><h2>${fa(i+1)} / ${f.title}</h2><p class="helper">${f.theme==='bright'?'کمی پرانرژی‌تر':'آرام'} · حالت ${f.state}</p></div>${phone(f.screen,f.state,f.theme,true)}</article>`).join('')}</div></div>`;
    }else document.getElementById('app').innerHTML=controls()+`<div class="preview-stage">${phone(screen,state,theme)}</div>`;
  }
  function navigate(id,variant='normal',palette=theme,recordHistory=true) {
    if(!screens.some(s=>s.id===id)) id='home';
    if(id!==screen) {if(recordHistory)history.push(screen);timerRunning=false;}
    screen=id;state=lookup(id).states.includes(variant)?variant:'normal';theme=['calm','bright'].includes(palette)?palette:'calm';toast='';
    const url=new URL(location.href);url.search='';url.searchParams.set('screen',screen);url.searchParams.set('state',state);url.searchParams.set('theme',theme);
    window.history.replaceState(null,'',url);render();
  }
  function reset(){tasks=initialTasks();answers=Array(10).fill(null);question=0;practiceAnswer=null;practiceChecked=false;selectedRole=null;consentChecked=false;actionChecked=false;timerRunning=false;timerSeconds=1500;timerRest=false;toast='';history=[];navigate('home');}
  document.addEventListener('click', event => {
    const target=event.target.closest('[data-action]');if(!target||target.disabled||target.closest('.board-panel'))return;
    const action=target.dataset.action;const [kind,...parts]=action.split(':');const value=parts.join(':');
    if(kind==='go')return navigate(value);
    if(kind==='state')return navigate(screen,value);
    if(kind==='theme')return navigate(screen,state,value);
    if(kind==='plan-range'){planRange=value;render();return;}
    if(kind==='plan-day'){planDay=Number(value);render();return;}
    if(kind==='role'){selectedRole=value;render();return;}
    if(action==='welcome-next')return selectedRole?navigate(selectedRole==='parent'?'parent-phone':'child-invite'):navigate('welcome','error');
    if(action==='back'){const last=history.pop()||(currentRole()==='parent'?'parent-home':'home');return navigate(last,'normal',theme,false);}
    if(action==='board'){const url=new URL(location.href);url.search='?board=1';window.history.replaceState(null,'',url);timerRunning=false;return render();}
    if(action==='preview')return navigate('home');
    if(action==='review-toggle'){reviewExpanded=!reviewExpanded;render();return;}
    if(kind==='toast'){toast=value;render();return;}
    if(kind==='start-task'){selectedTask=Number(value);navigate('task');return;}
    if(action==='task-focus'){tasks[selectedTask].status='started';navigate('focus');return;}
    if(action==='complete-task'){tasks[selectedTask].status=tasks[selectedTask].status==='completed'?'planned':'completed';toast='تیک فقط در حافظهٔ این طرح تغییر کرد.';render();return;}
    if(action==='sample-time'){tasks[selectedTask].time='۱۷:۰۰ تا ۱۷:۲۵';toast='زمان نمونه عوض شد؛ ذخیرهٔ واقعی انجام نشد.';render();return;}
    if(kind==='practice'){practiceAnswer=Number(value);practiceChecked=false;render();return;}
    if(action==='practice-check'){practiceChecked=true;render();return;}
    if(kind==='answer'){answers[question]=Number(value);render();return;}
    if(action==='quiz-next'){if(answers[question]===null)return;if(question<9){question++;render();}else navigate('quiz-result');return;}
    if(action==='quiz-retry'){question=0;answers=Array(10).fill(null);navigate('quiz');return;}
    if(action==='consent-check'){consentChecked=target.checked;render();return;}
    if(action==='action-check'){actionChecked=target.checked;render();return;}
    if(kind==='confirm'){pendingAction=value;actionChecked=false;navigate(currentRole()==='parent'?'parent-confirm-action':'confirm-action');return;}
    if(kind==='resolve'){navigate(screen);toast='انتخاب نمونه اعمال شد؛ هیچ همگام‌سازی واقعی انجام نشد.';render();return;}
    if(kind==='reminder'){remindOptions[Number(value)]=!remindOptions[Number(value)];render();return;}
    if(action==='timer-toggle'){timerRunning=!timerRunning;render();return;}
    if(action==='timer-break'){timerRunning=false;timerRest=true;timerSeconds=300;render();return;}
    if(action==='timer-stop'){timerRunning=false;toast='زمان فقط در طرح دیده شد؛ ذخیره یا ارسال نشده است.';navigate('plan');return;}
  });
  document.addEventListener('change', event=>{
    const control=event.target.dataset.control;if(!control)return;
    if(control==='screen')navigate(event.target.value);
    if(control==='state')navigate(screen,event.target.value);
    if(control==='theme')navigate(screen,state,event.target.value);
  });
  setInterval(()=>{if(timerRunning&&screen==='focus'&&timerSeconds>0){timerSeconds--;const el=document.querySelector('[data-qa=timer]');if(el)el.textContent=fa(String(Math.floor(timerSeconds/60)).padStart(2,'0'))+':'+fa(String(timerSeconds%60).padStart(2,'0'));}},1000);
  const url=new URL(location.href);screen=lookup(url.searchParams.get('screen')).id;state=lookup(screen).states.includes(url.searchParams.get('state'))?url.searchParams.get('state'):'normal';theme=url.searchParams.get('theme')==='bright'?'bright':'calm';
  window.LifeGuideDesign={screens,boardFrames,navigate,render,reset,questionCount:questions.length,sampleDataOnly:true,backendConnected:false};
  render();
})();
