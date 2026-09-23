import React, { useState} from 'react';
import { useToast, HStack, Tooltip, Container, Box, Fade, Grid, GridItem, Tabs, TabList, TabPanels, Tab, TabPanel, Kbd, IconButton, Accordion, AccordionItem, AccordionButton, AccordionPanel, AccordionIcon, Stack} from "@chakra-ui/react";
import './App.css'
import { debugData } from "../utils/debugData";
import { fetchNui } from "../utils/fetchNui";
import { Currentfareinfo } from "../interfaces/currentfareinfo";
import { Speed } from "../interfaces/speed";
import { useNuiEvent } from "../hooks/useNuiEvent";
import DocinfoList from './body/currentfareinfo';
import SpeedList from './body/speed';
import { Locale } from '../interfaces/locale';
import { FaUserAlt, FaCompass, FaDollarSign, FaSignInAlt } from 'react-icons/fa';
import Draggable from 'react-draggable';

interface VariableProps {
  currentfareinfo: Currentfareinfo;
  speed: Speed;
  fares: Array<any>;
  keybind: string;
}

interface Props extends VariableProps {}

interface ReturnData {
  success: boolean;
  reason: string;
}


const mockData: Props = {
  currentfareinfo: {
    "customer": "Karen Davis",
    "destination": "Legion Square",
    "distance": "600",
    "basefare": "100",
    "currentfare": "1000",
    "perminute": "2.00"
  },
  speed: {
    "velocity": 0,
  },
  fares: [
    {name: "Karen", id: 1, distance: 1400, payout: 1200},
    {name: undefined, id: 0},
    {name: "John", id: 2}
  ],
  keybind: 'N'
};

debugData([
  {
    action: "setData",
    data: mockData,
  },
])

const App: React.FC = () => {
  const toast = useToast()
  const [visible, setVisible] = useState(false);
  const [data, setData] = useState<Props>(mockData);
  const [tabIndex, setTabIndex] = useState(0);
  const handleTabsChange = (index:any) => {
    setTabIndex(index)
  }

  const focusJob = () => {
    setTabIndex(0)
  }

  useNuiEvent<{locale: {[key: string]: string}}>('setuplocale', ({locale}) => {
    for (const [name, data] of Object.entries(locale)) Locale[name] = data;
  });

  useNuiEvent<Props>("setData", (newData) => {
    setData((data) => ({ ...data, ...newData }));
  });

  useNuiEvent("setVisible", setVisible);

  return (
    <>
    <Fade in={visible}>
    <Draggable>
      <Box position='fixed' left='10px' top='10px'>
        <Container borderRadius={4} bg='#282c34' maxW='625px' text-align='center' padding='0px 0px 0px 0'>
          <Tabs variant='enclosed' isFitted={true} index={tabIndex} onChange={handleTabsChange}>
            <TabList>
              <Tab>{Locale.ui_activejob_header || 'Active Job'}</Tab>
              <Tab>{Locale.ui_fares_header || 'Fares'}</Tab>
            </TabList>
            <TabPanels>
              <TabPanel>
              <Grid h='215px' templateRows='repeat(2, 1fr)' templateColumns='repeat(5, 1fr)' gap={2} borderRadius={4} >
                <GridItem borderRadius={3} rowSpan={2} colSpan={1} bg='gray.800'>
                  <SpeedList speed={data.speed} />
                </GridItem>
                <GridItem borderRadius={3} colSpan={4} rowSpan={2} bg='gray.800'>
                  <DocinfoList currentfareinfo={data.currentfareinfo} />
                </GridItem>
              </Grid>
              </TabPanel>
              <TabPanel>
                <Accordion minH='215px' minW='600px' allowToggle overflowY={'auto'} overflowX={'hidden'} maxH='100px' css={{'&::-webkit-scrollbar': {width: '4px'}, '&::-webkit-scrollbar-track': {width: '4px'}, '&::-webkit-scrollbar-thumb': {background: 'var(--chakra-colors-blue-300)', borderRadius: '0px'}}}>
                  {data.fares.map((fare, index) => (
                    <div>
                      {fare?.name !== undefined && fare?.driver === undefined &&
                      <AccordionItem key={index}>
                      <h2>
                        <AccordionButton>
                          <Box as="span" flex='1' textAlign='left'>
                            <HStack><FaUserAlt /><p>{fare?.name}</p></HStack>
                          </Box>
                          <AccordionIcon />
                        </AccordionButton>
                      </h2>
                      <AccordionPanel pb={2}>
                        <Stack>
                          <HStack><FaCompass /><p>{fare.distance | 0.0}{Locale.ui_distance_unit || 'm'}</p></HStack>
                          <HStack><FaDollarSign /><p>{Locale.ui_currency || '$'}{fare.fare || 0.0}</p></HStack>
                          <Tooltip label={Locale.ui_accept_tooltip || 'Accept Job'}>
                            <IconButton aria-label='test' icon={<FaSignInAlt />} size='xs' borderRadius={3} bgColor={'green.500'} onClick={() =>
                              fetchNui<ReturnData>('takejob', {id: fare.id}).then(retData => {
                                retData.success == true && focusJob()
                              }).catch(e => {
                                console.log('Setting mock data due to error', e)
                                toast({title: 'LS Taxi', description: "Error Occured", status: 'error', duration: 4000, isClosable: true, position: 'top'})
                              })}>
                            </IconButton>
                          </Tooltip>
                        </Stack>
                      </AccordionPanel>
                    </AccordionItem>
                    }
                    </div>
                  ))}
                </Accordion>
              </TabPanel>
            </TabPanels>
          </Tabs>
          <span style={{position: 'relative', left: '16px', bottom: '10px', color: 'var(--chakra-colors-blue-300)', fontSize: '16px'}}>
              <Kbd fontSize={'16px'}>{data.keybind}</Kbd> - {Locale.ui_focus_label || 'Focus UI'}
          </span>
        </Container>
      </Box>
      </Draggable>
    </Fade>
  </>
  );
}

export default App;