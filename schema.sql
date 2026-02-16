/*
   Схема данных платформы IT Resume
   Источник: документация Simulative + information_schema
   Дата: 23.01.2026

   Таблицы, используемые в анализе retention:
   - users (пользователи)
   - userentry (входы)
   - coderun / codesubmit (решение задач)
   - teststart (тесты)
   - transaction (транзакции)
   - problem / language / languagetoproblem (контент)
*/

-- ============================================================
-- ПОЛЬЗОВАТЕЛИ
-- ============================================================

-- Таблица с информацией о всех пользователях
create table users (
    id integer primary key,
    username varchar not null,           -- логин на платформе
    first_name varchar,                   -- имя
    last_name varchar,                     -- фамилия
    email varchar not null,                 -- почта
    is_active integer not null,              -- 1 - активирован, 0 - нет
    date_joined timestamp not null,          -- дата и время регистрации
    referal_user integer references users(id), -- пользователь, который его пригласил
    company_id integer references company(id), -- для корпоративных клиентов
    tier integer not null,                     -- ранг на платформе
    score integer not null                      -- количество очков опыта
);

-- Комментарий: при анализе retention используются только физические лица
-- (id > 94 AND company_id IS NULL)

-- ============================================================
-- АКТИВНОСТИ ПОЛЬЗОВАТЕЛЕЙ
-- ============================================================

-- Фиксируются заходы пользователя на платформу
-- Важно: только первый вход в каждые сутки для одного пользователя!
create table userentry (
    id integer primary key,
    user_id integer not null references users(id),
    page_id integer not null references page(id),
    entry_at timestamp not null              -- дата и время входа
);

-- Комментарий: таблица заполняется не полностью,
-- поэтому для определения когорт используется любая первая активность

-- Запуски кода (пользователь нажал "Выполнить")
create table coderun (
    id integer primary key,
    user_id integer not null references users(id),
    problem_id integer not null references problem(id),
    language_id integer references language(id),
    created_at timestamp not null              -- дата и время выполнения
);

-- Отправки на проверку (пользователь нажал "Проверить")
create table codesubmit (
    id integer primary key,
    user_id integer not null references users(id),
    problem_id integer not null references problem(id),
    language_id integer references language(id),
    code text not null,                         -- код, написанный пользователем
    is_false smallint not null,                  -- 0 - успешно, 1 - ошибка
    time_spent varchar,                           -- время выполнения кода
    created_at timestamp not null                  -- дата и время проверки
);

-- Начало прохождения тестов (нажатие "Начать тест")
create table teststart (
    id integer primary key,
    user_id integer not null references users(id),
    test_id integer not null references test(id),
    created_at timestamp not null                  -- дата и время начала
);

-- Результаты тестов (ответы на вопросы)
-- Важно: 1 строка = 1 вопрос теста
create table testresult (
    id integer primary key,
    user_id integer not null references users(id),
    test_id integer not null references test(id),
    question_id integer not null references testquestion(id),
    answer_id integer references testanswer(id),   -- может быть NULL, если вопрос пропущен
    value varchar,                                   -- если пользователь вводил ответ вручную
    created_at timestamp not null                    -- дата и время ответа
);

-- ============================================================
-- КОНТЕНТ: ЗАДАЧИ
-- ============================================================

-- Языки программирования
create table language (
    id integer primary key,
    name varchar not null                  -- название языка
);

-- Задачи
create table problem (
    id integer primary key,
    name varchar not null,                  -- название задачи
    task text not null,                      -- формулировка задания
    solution text not null,                   -- формулировка решения
    complexity integer not null,               -- сложность (1-3)
    bonus integer not null,                     -- бонус за правильное решение (CodeCoins)
    cost integer not null,                       -- стоимость задачи (CodeCoins)
    solution_cost smallint not null,              -- стоимость просмотра решения (CodeCoins)
    rating numeric,                                -- рейтинг задачи
    priority numeric not null,                     -- приоритет отображения
    page_id integer not null references page(id),
    company_id integer references company(id),      -- для корпоративных задач
    is_visible boolean,                              -- отображать в общем списке?
    is_private boolean,                               -- только для корпоративных?
    recommendation text                                -- рекомендации по решению
);

-- Связь задач с языками (1 задача = несколько языков)
create table languagetoproblem (
    ltp_id integer primary key,
    pr_id integer not null references problem(id),
    lang_id integer not null references language(id)
);

-- Домашние задания для компаний (корпоративных клиентов)
-- Переопределяет параметры задачи для конкретной компании
create table problem_to_company (
    id integer primary key,
    company_id integer not null references company(id),
    problem_id integer not null references problem(id),
    name varchar,                                -- кастомное название
    task text,                                    -- кастомная формулировка
    cost smallint,                                -- кастомная стоимость
    bonus smallint,                               -- кастомный бонус
    priority numeric,                              -- кастомный приоритет
    unique(company_id, problem_id)
);

-- ============================================================
-- КОНТЕНТ: ТЕСТЫ
-- ============================================================

-- Тесты
create table test (
    id integer primary key,
    name varchar not null,                  -- название теста
    intro varchar not null,                  -- текст-введение
    result varchar not null,                  -- результаты (3 варианта, через запятую)
    cover varchar not null,                    -- обложка (путь до картинки)
    complexity smallint not null,               -- сложность (1-3)
    cost integer not null,                       -- стоимость прохождения (CodeCoins)
    repeat_cost integer not null,                 -- стоимость повторного прохождения
    priority numeric not null,                     -- приоритет отображения
    page_id integer not null references page(id),
    company_id integer references company(id),
    is_visible boolean,                             -- отображать в списке?
    is_private boolean                               -- приватный тест?
);

-- Вопросы к тестам
create table testquestion (
    id integer primary key,
    test_id integer not null references test(id),
    question_num integer,                          -- номер вопроса в тесте
    value text not null,                            -- текст вопроса
    tag varchar not null,                            -- основная тема вопроса
    type_question varchar,                            -- тип вопроса (выбор/множественный/ввод)
    explanation text not null,                         -- объяснение вопроса
    explanation_cost integer not null                   -- стоимость объяснения (CodeCoins)
);

-- Варианты ответов
create table testanswer (
    id integer primary key,
    question_id integer not null references testquestion(id),
    value text not null,                          -- текст ответа
    option integer,                                -- номер варианта (1-4)
    is_correct boolean not null                    -- правильный ли ответ
);

-- ============================================================
-- ТРАНЗАКЦИИ (ВНУТРЕННЯЯ ВАЛЮТА)
-- ============================================================

-- Типы транзакций (движения CodeCoins)
-- type 1, 23-28: списание
-- type 2-22, 29: начисление
-- type 30: покупка за рубли (можно игнорировать)
create table transactiontype (
    type smallint primary key,                 -- идентификатор типа
    description varchar not null,               -- описание
    value smallint,                              -- количество CodeCoins по умолчанию
    is_visible integer not null,
    reason varchar,
    icon varchar,
    button varchar not null,
    tooltip text not null,
    destination_id integer,
    allowed_for varchar
);

-- Все движения CodeCoins пользователей
create table transaction (
    id integer primary key,
    user_id integer not null references users(id),
    type_id smallint not null references transactiontype(type),
    value smallint,                              -- сумма транзакции
    created_at timestamp not null                  -- дата и время
);

-- ============================================================
-- КОМПАНИИ (КОРПОРАТИВНЫЕ КЛИЕНТЫ)
-- ============================================================

create table company (
    id integer primary key,
    name varchar not null,                       -- название компании
    description text not null,                    -- описание
    logo varchar,                                  -- логотип (путь до файла)
    site varchar,                                  -- ссылка на сайт
    db_cred varchar,                               -- информация о схеме БД для обработки кода
    welcome_bonus smallint                          -- приветственный бонус (CodeCoins)
);

-- ============================================================
-- СТРАНИЦЫ (ДЛЯ НАВИГАЦИИ)
-- ============================================================

create table page (
    id integer primary key,
    path varchar not null,                        -- относительный URL
    name varchar not null,                         -- имя страницы
    title varchar,                                  -- meta title
    description varchar,                            -- meta description
    keywords varchar                                -- meta keywords (через запятую)
);

-- ============================================================
-- ПРИМЕЧАНИЯ ПО АНАЛИЗУ
-- ============================================================

/*
1. Критерии отбора пользователей для анализа:
   - id > 94 (исключаем внутренних пользователей)
   - company_id IS NULL (только физические лица)
   
2. Проблемы с данными:
   - userentry заполняется не полностью (только первый вход в сутки)
   - testresult и transaction появились позже других таблиц
   - Нет логов навигации по платформе (только факт входа на страницу)

3. Для когортного анализа используется дата первой любой активности:
   - userentry (если есть)
   - coderun / codesubmit
   - teststart
   - transaction
   
4. Сегментация пользователей:
   - only tests: есть в teststart, нет в codesubmit/coderun
   - only problems: есть в codesubmit/coderun, нет в teststart
   - tests and problems: есть и там, и там
   - no activity: нет нигде (только userentry)
*/