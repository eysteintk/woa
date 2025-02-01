// app/components/layout/panels/world/WorldPanel.tsx
'use client';

import React, { useEffect } from 'react';
import { EChartsViz } from '@/components/ui/EChartsViz';
import { useData } from '@/context/DataContext';

export default function WorldPanel() {
  const { handleJoinGroup } = useData();

  useEffect(() => {
    // join the world group on mount
    handleJoinGroup('world');
  }, [handleJoinGroup]);

  const option = {
    title: { text: 'World View' },
    tooltip: { trigger: 'item' },
    xAxis: {},
    yAxis: {},
    series: [{
      type: 'scatter',
      data: [[1,2],[2,6],[3,3]],
      symbolSize: 10
    }]
  };

  const onEvents = {};

  return <EChartsViz option={option} style={{width:'100%', height:'100%'}} onEvents={onEvents} />;
}
