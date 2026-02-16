/*
   Анализ удержания пользователей (Retention) платформы IT Resume
   
   Автор: Гребенкина Наталья
   Дата: 23.01.2026
   
   Тип проекта: Ad-hoc аналитический запрос
   Контекст: Продуктовый анализ для подготовки к переходу на подписочную модель
   
   Структура скрипта:
     1. Проверка данных и временных интервалов
     2. Фильтрация пользователей
     3. Формирование когорт
     4. Расчет retention метрик
     5. Сегментный анализ по типам активности
     6. Анализ первого дня
*/


-- 1. ПРОВЕРКА ДАННЫХ

-- Определяем доступный временной диапазон в каждой таблице
select
	'userentry' as data_source,
	min(entry_at)::date as first_date,
	max(entry_at)::date as last_date
from userentry u
union all
select
	'coderun',
	min(created_at)::date,
	max(created_at)::date
from coderun cr
union all
select
	'codesubmit',
	min(created_at)::date,
	max(created_at)::date
from codesubmit cs
union all
select
	'testresult',
	min(created_at)::date,
	max(created_at)::date
from testresult ts
union all
select
	'transaction',
	min(created_at)::date,
	max(created_at)::date
from transaction t
order by first_date;

/*
 Результат:
 
data_source|first_date|last_date |
-----------+----------+----------+
coderun    |2021-03-27|2022-05-17|
codesubmit |2021-03-28|2022-05-17|
userentry  |2021-03-29|2022-05-24|
testresult |2021-05-24|2022-05-16|
transaction|2021-06-23|2022-05-24|

Выводы:
- наблюдается рассогласованность дат в логах: данные о входе (userentry) 
  стали записываться позже, чем о решении задач (coderun и codesubmit)
- для определения когорты будет использоваться дата любой первой активности 
  пользователя, чтобы нивелировать неполноту данных по входам
*/


-- 2. ФИЛЬТРАЦИЯ ПОЛЬЗОВАТЕЛЕЙ

-- Оставляем только физических лиц (целевая аудитория)
-- id > 94 исключает внутренних пользователей, company_id is null исключает корпоративных
create temp table clean_users as
	select
		id as user_id,
		case when referal_user is not null then 1 else 0 end as is_referrer,
		is_active  -- добавляем флаг реферального пользователя
	from users u 
	where u.id > 94
		and u.company_id is null;

-- Выводим статистику по отфильтрованным пользователям
select 
	count (*) as ctn_clean_users,
	round(sum(is_referrer) * 100.0 / count (*), 2) as share_referal_users,
	round(sum(is_active) * 100.0 / count (*), 2) as share_activated_users
from clean_users;

/*
 Результат:
 
 ctn_clean_users|share_referal_users|share_activated_users|
---------------+-------------------+---------------------+
           2459|               2.77|                88.78|
 
Выводы:
 - 2459 пользователей, 2.8% реферальных, 88.8% активированных
 - подавляющее большинство пользователей соответствуют портрету «активировал аккаунт, не реферал»
 */


-- 3. ФОРМИРОВАНИЕ КОГОРТ

-- Определяем первую и последнюю активность для каждого пользователя
create temp table user_cohorts as
with user_activities as (-- собираем информацию обо всех активностях пользователей из выборки
	select
		user_id,
		min(entry_at) as first_activity,
		max(entry_at) as last_activity
	from userentry ue
	where user_id in (select user_id from clean_users)
	group by user_id
	union all
	select
		user_id,
		min(created_at),
		max(created_at)
	from coderun cr
	where user_id in (select user_id from clean_users)
	group by user_id
	union all
	select
		user_id,
		min(created_at),
		max(created_at)
	from codesubmit cs
	where user_id in (select user_id from clean_users)
	group by user_id
	union all
	select
		user_id,
		min(created_at),
		max(created_at)
	from transaction t
	where user_id in (select user_id from clean_users)
	group by user_id
)
select  -- формируем когорты пользователей
	user_id,
	to_char(min(first_activity), 'YYYY-MM') as cohort,
	min(first_activity) as first_activity,
	max(last_activity) as last_activity,
	extract(day from max(last_activity) - min(first_activity)) as max_day
from user_activities
group by user_id;

-- Выводим количество записей в таблице
select count(*)
from user_cohorts;

/*
 Результат:
 
 count|
-----+
 2153|
 */


-- 4. АНАЛИЗ КОГОРТ

-- Рассчитываем базовые статистики по каждой когорте
select
	cohort,
	count(user_id) as total_users,
	percentile_cont(0.5) within group (order by max_day)::numeric(10, 2) as median_lifetime,
	avg(max_day)::numeric(10, 2) as avg_lifetime,
	max(max_day) as max_lifetime,
	extract(day from (select max(entry_at) from userentry) - min(first_activity)) as total_days -- до последней записи в данных
from user_cohorts
group by cohort
order by cohort;

/*
 Результат:
 
 cohort |total_users|median_lifetime|avg_lifetime|max_lifetime|total_days|
-------+-----------+---------------+------------+------------+----------+
2021-11|        141|          27.00|       50.74|       185.0|     185.0|
2021-12|        100|           0.00|       20.27|       152.0|     174.0|
2022-01|        481|           0.00|       11.50|       129.0|     142.0|
2022-02|        900|           0.00|        6.11|       106.0|     112.0|
2022-03|        387|           0.00|        4.47|        75.0|      84.0|
2022-04|        143|           0.00|        4.34|        49.0|      53.0|
2022-05|          1|           0.00|        0.00|         0.0|      12.0|

Вывод: падение средней продолжительности жизни с 50 до 4 дней за 5 месяцев,
>50% пользователей уходят в первый день начиная с декабря
 */

-- Определяем rolling retention по когортам
select
	cohort,
	count(user_id) as cnt_users,
	round(count(user_id) filter (where max_day >= 0) * 100.0 / count(user_id), 2) as d0_r_retention,
	round(count(user_id) filter (where max_day >= 1) * 100.0 / count(user_id), 2) as d1_r_retention,
	round(count(user_id) filter (where max_day >= 3) * 100.0 / count(user_id), 2) as d3_r_retention,
	round(count(user_id) filter (where max_day >= 7) * 100.0 / count(user_id), 2) as d7_r_retention,
	round(count(user_id) filter (where max_day >= 14) * 100.0 / count(user_id), 2) as d14_r_retention,
	round(count(user_id) filter (where max_day >= 30) * 100.0 / count(user_id), 2) as d30_r_retention,
	round(count(user_id) filter (where max_day >= 60) * 100.0 / count(user_id), 2) as d60_r_retention
from user_cohorts
group by cohort
order by cohort;

/*
 Результат:
 
 cohort |cnt_users|d0_r_retention|d1_r_retention|d3_r_retention|d7_r_retention|d14_r_retention|d30_r_retention|d60_r_retention|
-------+---------+--------------+--------------+--------------+--------------+---------------+---------------+---------------+
2021-11|      141|        100.00|         65.25|         59.57|         56.74|          55.32|          48.94|          35.46|
2021-12|      100|        100.00|         41.00|         33.00|         32.00|          26.00|          23.00|          16.00|
2022-01|      481|        100.00|         37.42|         31.19|         25.99|          21.83|          12.89|           7.07|
2022-02|      900|        100.00|         26.67|         18.78|         14.11|          10.78|           7.56|           4.44|
2022-03|      387|        100.00|         27.13|         21.45|         15.25|          11.37|           6.20|           0.52|
2022-04|      143|        100.00|         32.87|         25.17|         18.88|          14.69|           3.50|           0.00|
2022-05|        1|        100.00|          0.00|          0.00|          0.00|           0.00|           0.00|           0.00|
 
 Выводы:
- Месячное удержание к февралю упало в 6 раз (48.9% → 7.6%)
- Основной отток сместился на первый день
- Даже преодолевшие начальный барьер стали уходить быстрее
*/


-- 5. СЕГМЕНТАЦИЯ ПО ТИПАМ АКТИВНОСТИ

-- Определяем паттерны поведения пользователей
explain(analyse, buffers)
create temp table activity_kind as (
	select 
		uc.user_id,
		uc.cohort,
		uc.max_day,
		case when p.user_id  is not null and  t.user_id is not null then 'tests and problems'
			when p.user_id  is not null then 'only problems'
			when t.user_id is not null then 'only tests'
			else 'no activity' end as activity_type -- определяем тип активности пользователя 
	from user_cohorts uc
	left join (select
					user_id
				from codesubmit cs
				union
				select
					user_id
				from coderun cr) p using(user_id)
	left join (select
					distinct user_id
				from teststart) t using(user_id)
);


-- Рассчитываем rolling retention по типам поведения
select
	activity_type,
	count(user_id) as cnt_users,
	round(count(user_id) filter (where max_day >= 0) * 100.0 / count(user_id), 2) as d0_r_retention,
	round(count(user_id) filter (where max_day >= 1) * 100.0 / count(user_id), 2) as d1_r_retention,
	round(count(user_id) filter (where max_day >= 3) * 100.0 / count(user_id), 2) as d3_r_retention,
	round(count(user_id) filter (where max_day >= 7) * 100.0 / count(user_id), 2) as d7_r_retention,
	round(count(user_id) filter (where max_day >= 14) * 100.0 / count(user_id), 2) as d14_r_retention,
	round(count(user_id) filter (where max_day >= 30) * 100.0 / count(user_id), 2) as d30_r_retention,
	round(count(user_id) filter (where max_day >= 60) * 100.0 / count(user_id), 2) as d60_r_retention
from activity_kind
group by activity_type
order by d60_r_retention desc;

/*
 Результат:
 
 activity_type     |cnt_users|d0_r_retention|d1_r_retention|d3_r_retention|d7_r_retention|d14_r_retention|d30_r_retention|d60_r_retention|
------------------+---------+--------------+--------------+--------------+--------------+---------------+---------------+---------------+
tests and problems|      332|        100.00|         71.99|         61.45|         55.42|          47.89|          37.95|          24.40|
only problems     |      425|        100.00|         47.06|         37.18|         30.59|          25.18|          16.47|           8.71|
no activity       |      573|        100.00|         20.07|         14.31|         10.99|           9.08|           4.54|           2.44|
only tests        |      823|        100.00|         18.35|         13.49|          8.87|           6.44|           3.52|           1.22|
 
 Выводы:
 - комбинированная активность дает в 10x лучший retention, чем только тесты
 - сегмент only tests самый многочисленный
*/


-- Определяем динамику типов поведения по когортам
select 
	cohort,
	activity_type,
	round(count(*) * 100.0 / sum(count(user_id)) over (partition by cohort), 2) as share_users,
	avg(max_day)::numeric(10,2) as avg_lifetime
from activity_kind
group by cohort, activity_type
order by cohort, avg_lifetime desc;

/*
 Результат:
 
 cohort |activity_type     |share_users|avg_lifetime|
-------+------------------+-----------+------------+
2021-11|tests and problems|      41.84|       81.54|
2021-11|only problems     |      21.28|       54.63|
2021-11|only tests        |      10.64|       14.87|
2021-11|no activity       |      26.24|       13.03|
2021-12|tests and problems|      19.00|       51.05|
2021-12|only problems     |      26.00|       24.38|
2021-12|only tests        |      15.00|       19.33|
2021-12|no activity       |      40.00|        3.33|
2022-01|tests and problems|      18.30|       29.45|
2022-01|only problems     |      18.50|       17.83|
2022-01|no activity       |      22.45|        5.29|
2022-01|only tests        |      40.75|        3.99|
2022-02|tests and problems|      11.22|       20.66|
2022-02|only problems     |      18.67|        9.46|
2022-02|no activity       |      24.89|        3.83|
2022-02|only tests        |      45.22|        2.36|
2022-03|tests and problems|      12.66|        9.37|
2022-03|only problems     |      19.90|        8.16|
2022-03|no activity       |      27.91|        3.38|
2022-03|only tests        |      39.53|        1.82|
2022-04|tests and problems|      11.19|       14.13|
2022-04|only problems     |      24.48|        4.77|
2022-04|only tests        |      25.87|        2.73|
2022-04|no activity       |      38.46|        2.31|
2022-05|no activity       |     100.00|        0.00|
 
Вывод: доля ценного сегмента tests and problems упала с 41.8% до 11.2%,
а доля "тупикового" only tests выросла с 10.6% до 45.2%
 */


-- 6. АНАЛИЗ ПЕРВОГО ДНЯ

-- Определяем, какие задачи решают пользователи в первые 24 часа
with problems_activity as (
	select
		user_id,
		cohort,
		max_day,
		problem_id
	from coderun cr
	join user_cohorts uc using(user_id)
	where cr.created_at <= uc.first_activity + interval '24 hours'
	group by user_id, cohort, max_day, problem_id
	union
	select
		user_id,
		cohort,
		max_day,
		problem_id
	from codesubmit cr
	join user_cohorts uc using(user_id)
	where cr.created_at <= uc.first_activity + interval '24 hours'
	group by user_id, cohort, max_day, problem_id
),
problem_rating as (
	select
			cohort,
			problem_id,
			count(distinct user_id) as cnt_users,
			avg(max_day) as avg_lifetime,
			dense_rank() over (partition by cohort order by count(distinct user_id) desc) as rank
	from problems_activity
	group by cohort, problem_id
),
cohort_size as (
    select 
        cohort, 
        count(user_id) as total_users 
    from user_cohorts 
    group by cohort
)
select
	pr.cohort,
	p.name,
	l.name as language,
	p.complexity,
	cnt_users,
	round(cnt_users * 100.0 / total_users, 2) as share_users,
    pr.avg_lifetime::numeric(10,2) as avg_lifetime_days,
	rank
from problem_rating pr
left join problem p on pr.problem_id = p.id
left join cohort_size cs on pr.cohort = cs.cohort
left join languagetoproblem lp on pr.problem_id = lp.pr_id
left join language l on lp.lang_id = l.id
where rank <= 3
order by cohort, rank;

/*
 Результат:
 
 cohort |name                                                      |language|complexity|cnt_users|share_users|avg_lifetime_days|rank|
-------+----------------------------------------------------------+--------+----------+---------+-----------+-----------------+----+
2021-11|TOP ↑ | Поиск самого частого символа                      |Python  |         1|       20|      14.18|            62.55|   1|
2021-11|TOP ↑ | Задача FizzBuzz                                   |Python  |         1|       18|      12.77|            47.50|   2|
2021-11|TOP ↑ | Продажи анализов в течение недели                 |SQL     |         1|       14|       9.93|            60.21|   3|
2021-12|Неубывающий массив                                        |Python  |         2|        8|       8.00|            48.38|   1|
2021-12|TOP ↑ | Задача FizzBuzz                                   |Python  |         1|        5|       5.00|            17.00|   2|
2021-12|ООП: Кастомный класс целых чисел                          |Python  |         1|        5|       5.00|            11.00|   2|
2021-12|NEW! | По дороге с облаками                               |Python  |         1|        4|       4.00|            29.25|   3|
2022-01|[Тестовое Альфа-банк] Покупки товара после 10 октября 2021|SQL     |         1|       74|      15.38|            27.72|   1|
2022-01|[Avito Weekend Offer] Найти медиану                       |Python  |         1|       56|      11.64|            23.80|   2|
2022-01|[Тестовое Альфа-банк] Покупки телефонов в Туле по месяцам |SQL     |         2|       39|       8.11|            26.15|   3|
2022-02|[Тестовое Альфа-банк] Покупки товара после 10 октября 2021|SQL     |         1|      111|      12.33|            13.05|   1|
2022-02|[Avito Weekend Offer] Найти медиану                       |Python  |         1|       43|       4.78|            13.74|   2|
2022-02|[Тестовое Альфа-банк] Покупки телефонов в Туле по месяцам |SQL     |         2|       30|       3.33|             7.10|   3|
2022-03|[Тестовое Альфа-банк] Покупки телефонов в Туле по месяцам |SQL     |         2|       27|       6.98|             7.41|   1|
2022-03|[Avito Weekend Offer] Пересечение без дубликатов          |Python  |         1|       24|       6.20|             8.96|   2|
2022-03|[СБЕР: Junior DE & DS] Разложение на простые множители    |Python  |         1|       23|       5.94|            12.43|   3|
2022-04|[Тестовое Альфа-банк] Покупки телефонов в Туле по месяцам |SQL     |         2|       10|       6.99|            12.00|   1|
2022-04|[СБЕР: Junior DE & DS] Разложение на простые множители    |Python  |         1|        9|       6.29|             5.78|   2|
2022-04|[Тестовое Альфа-банк] Покупки товара после 10 октября 2021|SQL     |         1|        8|       5.59|             9.75|   3|

Вывод: произошла смена парадигмы - вместо учебных задач в топ вышли
корпоративные тестовые задания, что совпало с обвалом retention
*/


-- 7. ОЧИСТКА ВРЕМЕННЫХ ТАБЛИЦ
drop table if exists clean_users;
drop table if exists user_cohorts;
drop table if exists user_behavior;