-- Teste de desempenho: gera 100 mil veículos e compara a busca de disponíveis
-- SEM e COM índice. Rode DEPOIS do 01_schema_migracao_consultas.sql
-- (na mesma base). Anote no relatório o plano que aparecer em cada EXPLAIN.

WITH RECURSIVE n(i) AS (SELECT 1 UNION ALL SELECT i+1 FROM n WHERE i < 100000)
INSERT INTO Veiculos (placa, marca, modelo, ano, status)
SELECT 'T' || printf('%06d', i), 'Marca', 'Modelo', 2020,
       CASE WHEN i % 20 = 0 THEN 'Disponível' ELSE 'Alugado' END
FROM n;

-- SEM índice
DROP INDEX idx_veiculos_status;
EXPLAIN QUERY PLAN SELECT id_veiculo, placa FROM Veiculos WHERE status = 'Disponível';
-- esperado: SCAN Veiculos (varre a tabela inteira)

-- COM índice
CREATE INDEX idx_veiculos_status ON Veiculos(status);
EXPLAIN QUERY PLAN SELECT id_veiculo, placa FROM Veiculos WHERE status = 'Disponível';
-- esperado: SEARCH Veiculos USING (COVERING) INDEX idx_veiculos_status (status=?)
