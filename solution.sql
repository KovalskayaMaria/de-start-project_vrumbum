-- Этап 1. Создание и заполнение БД
create schema if not exists raw_data;

CREATE TABLE raw_data.sales (
    id INT PRIMARY KEY, -- вероятно, можно также использовать smallint исходя из количества записей за 7 лет продаж
    auto VARCHAR(100), -- или TEXT, если я правильно понимаю также допустим
    gasoline_consumption numeric(4,2), -- в таблице один знак после запятой, на всякий случай оставляю 2. 
    -- двух разрядов перед запятой будет достаточно, даже если в таблице есть грузовые автомобили
    price MONEY, -- денежный тип данных, в нашем случае точности в 2 знака после запятой будет достаточно
    date DATE, -- или timestamp
    person_name VARCHAR(50), -- или TEXT, если я правильно понимаю, также допустим
    phone VARCHAR(30), -- или TEXT, если я правильно понимаю, также допустим
    discount INT, -- целое от 0 до 100
    brand_origin VARCHAR(20)  -- или TEXT, если я правильно понимаю, также допустим
);

\copy raw_data.sales(id,auto,gasoline_consumption,price,date,person_name,phone,discount,brand_origin) FROM 'C:\Temp\cars.csv' DELIMITER ',' CSV HEADER NULL 'null';

--создаю схему
create schema if not exists car_shop;

-- создаюи и наполняю значениями таблицу 1 стран-производителей
CREATE TABLE car_shop.countries (
    id serial PRIMARY KEY, -- сгенерится автоматически во время вставки
    country_name VARCHAR(20) not null unique -- или TEXT
);

insert into car_shop.countries (country_name)
select distinct brand_origin
    from raw_data.sales
where brand_origin is not null
order by brand_origin asc; --просто для красоты

-- создаю и наполняю значениями таблицу 2 с цветами автомобилей
CREATE TABLE car_shop.colours (
    id serial PRIMARY KEY, -- сгенерится автоматически во время вставки
    colour_name VARCHAR(20) not null unique -- или TEXT
);

insert into car_shop.colours (colour_name)
select distinct split_part(s.auto, ', ', 2) as colour
    from raw_data.sales s
order by colour; --просто для красоты

-- создаю и наполняю значениями таблицу 3 с покупателями
CREATE TABLE car_shop.clients (
    id serial PRIMARY KEY, -- сгенерится автоматически во время вставки
    first_name VARCHAR(20) not null, -- или TEXT
    last_name VARCHAR(20) not null, -- или TEXT
    phone VARCHAR(30) not null,--имени и фамилии недостаточно для идентификации клиента в данном случае, поэтому поле должно быть заполнено
    unique (first_name, last_name, phone) --не может быть нескольких клиентов с одинаковым номеров, связка всех полей должна быть уникальна
);

select distinct s.person_name --проверяю, могу ли использовать в качестве разделителя для имени и фамилии пробел - считаю кол-во пробелов
-- в строке и вывожу имена(39 уникальных записей), в которых пробелов меньше/больше, делаю вывод что в столбце есть посторонняя информация, 
-- относящаяся к семейному положению и специальности, которой можно пренебречь для моих целей
    from raw_data.sales s
    where (length(s.person_name) - length(replace(s.person_name, ' ', ''))) <> 1;

insert into car_shop.clients (first_name, last_name, phone)
select distinct
    split_part(replace(replace(replace(replace(s.person_name, 'Miss ', ''), 'Mrs. ', ''), 'Mr. ', ''), 'Dr. ', ''), ' ', 1) as first_name,
    split_part(replace(replace(replace(replace(s.person_name, 'Miss ', ''), 'Mrs. ', ''), 'Mr. ', ''), 'Dr. ', ''), ' ', 2) as last_name,
    s.phone
from raw_data.sales s
order by last_name;

-- создаю и наполняю значениями таблицу 4 с брендами авто
CREATE TABLE car_shop.auto_brands (
    id serial PRIMARY KEY, -- сгенерится автоматически во время вставки
    brand_name VARCHAR(20) not null unique, -- или TEXT
    country_id int REFERENCES car_shop.countries (id)
);

insert into car_shop.auto_brands (brand_name, country_id)
select distinct 
    split_part(s.auto, ' ', 1) as brand,
    cn.id as country_id
    from raw_data.sales s left join car_shop.countries cn on cn.country_name = s.brand_origin
order by brand asc; --просто для красоты

-- создаю и наполняю значениями таблицу 5 с моделями авто
CREATE TABLE car_shop.auto_models (
    id serial PRIMARY KEY, -- сгенерится автоматически во время вставки
    model_name VARCHAR(20) not null, -- или TEXT
    brand_id int not null REFERENCES car_shop.auto_brands (id),
    gasoline_consumption numeric(4,2)
);

insert into car_shop.auto_models (model_name, brand_id, gasoline_consumption)
select distinct
    substr(s.auto, strpos(s.auto, ' ') + 1, strpos(s.auto, ',') - strpos(s.auto, ' ') - 1) as model_name,
    b.id as brand_id,
    s.gasoline_consumption
from raw_data.sales s  left join car_shop.auto_brands b on split_part(s.auto, ' ', 1) = b.brand_name
order by brand_id asc; --просто для красоты

-- создаю и наполняю значениями таблицу 6 с продажами
CREATE TABLE car_shop.purchases (
    id serial PRIMARY KEY, -- сгенерится автоматически во время вставки
    client_id int not null REFERENCES car_shop.clients (id),
    model_id int not null REFERENCES car_shop.auto_models (id),
    colour_id int not null REFERENCES car_shop.colours (id),
    date DATE not null,
    price MONEY not null, -- или TEXT
    discount int not null default 0 check (discount >= 0 and discount < 100)   
);

insert into car_shop.purchases (client_id, model_id, colour_id, date, price, discount)
select
    cl.id as client_id,
    m.id as model_id,
    c.id as colour_id,
    s.date,
    s.price,
    s.discount
from raw_data.sales s
left join car_shop.clients cl on 
    split_part(replace(replace(replace(replace(s.person_name, 'Miss ', ''), 'Mrs. ', ''), 'Mr. ', ''), 'Dr. ', ''), ' ', 1) = cl.first_name
    and split_part(replace(replace(replace(replace(s.person_name, 'Miss ', ''), 'Mrs. ', ''), 'Mr. ', ''), 'Dr. ', ''), ' ', 2) = cl.last_name
    and s.phone = cl.phone
left join car_shop.auto_models m on
    substr(s.auto, strpos(s.auto, ' ') + 1, strpos(s.auto, ',') - strpos(s.auto, ' ') - 1) = m.model_name
left join car_shop.colours c on
    split_part(s.auto, ', ', 2) = c.colour_name
order by s.date asc; --просто для красоты


-- Этап 2. Создание выборок
---- Задание 1
select count (*) filter (where am.gasoline_consumption is null)::real / count (*) * 100 as nulls_percentage_gasoline_consumption
from car_shop.auto_models am;

---- Задание 2
select 
    ab.brand_name as brand,
    DATE_PART ('year', p.date) as year,
    round(AVG(p.price::numeric), 2)::money as price_avg
from car_shop.purchases p
left join car_shop.auto_models am on am.id = p.model_id
left join car_shop.auto_brands ab on ab.id = am.brand_id
group by brand, year
order by brand, year;

---- Задание 3
select 
    DATE_PART ('month', p.date) as month,
    DATE_PART ('year', p.date) as year,
    round(AVG(p.price::numeric), 2)::money as price_avg
from car_shop.purchases p
group by month, year
order by year, month;

---- Задание 4
select 
    CONCAT(c.first_name, ' ', c.last_name) as person,
    STRING_AGG(CONCAT(ab.brand_name, ' ', am.model_name), ', ') as cars
from car_shop.purchases p
left join car_shop.clients c on c.id = p.client_id
left join car_shop.auto_models am  on am.id = p.model_id
left join car_shop.auto_brands ab  on ab.id = am.brand_id
group by person
order by person;

---- Задание 5
select 
    c.country_name  as brand_origin,
    MAX(p.price::numeric / (1 - p.discount / 100))::money as price_max,
    MIN(p.price::numeric / (1 - p.discount / 100))::money as price_min
from car_shop.purchases p
left join car_shop.auto_models am  on am.id = p.model_id
left join car_shop.auto_brands ab  on ab.id = am.brand_id
left join car_shop.countries c on c.id = ab.country_id
where c.country_name is not null
group by brand_origin
order by brand_origin;

--выборка 6
select count (*) as persons_from_usa_count
from car_shop.clients c
where substr (c.phone, 1, 2) = '+1';

