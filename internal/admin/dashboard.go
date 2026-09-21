package admin

import "context"

type Category struct {
	Key         string
	Label       string
	Description string
	Count       int
}

func (s *Store) Categories(ctx context.Context) ([]Category, error) {
	rows, err := s.pool.Query(ctx, `
        SELECT c.key,c.label,c.description,count(a.key)::int
        FROM app_setting_categories c
        LEFT JOIN app_settings a ON a.category=c.key
        GROUP BY c.key,c.label,c.description,c.sort_order
        ORDER BY c.sort_order,c.key`)
	if err != nil { return nil, err }
	defer rows.Close()
	var result []Category
	for rows.Next() {
		var item Category
		if err := rows.Scan(&item.Key,&item.Label,&item.Description,&item.Count); err != nil { return nil, err }
		result = append(result,item)
	}
	return result, rows.Err()
}
